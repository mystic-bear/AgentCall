#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";

const REQUIRED_KEYS = [
  "schema_version",
  "agent",
  "summary",
  "decisions",
  "risks",
  "open_questions",
  "action_items",
  "requested_context",
  "status",
  "needs_human_decision",
  "confidence",
];

const TYPE_EXPECTATIONS = {
  confidence: "number",
  needs_human_decision: "boolean",
  decisions: "array",
  risks: "array",
  open_questions: "array",
  action_items: "array",
  requested_context: "array",
};

function parseArgs(argv) {
  const args = {
    bodyFile: "",
    schemaFile: "",
    disableTypeChecks: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--body-file") {
      args.bodyFile = argv[index + 1] ?? "";
      index += 1;
    } else if (arg === "--schema-file") {
      args.schemaFile = argv[index + 1] ?? "";
      index += 1;
    } else if (arg === "--disable-type-checks") {
      args.disableTypeChecks = true;
    } else {
      throw new Error(`unknown arg: ${arg}`);
    }
  }

  if (!args.bodyFile) {
    throw new Error("--body-file is required");
  }
  return args;
}

function typeName(value) {
  if (Array.isArray(value)) return "array";
  if (value === null) return "null";
  return typeof value;
}

function extractJsonBlock(bodyText) {
  const lines = bodyText.split(/\r?\n/);
  let inBlock = false;
  const captured = [];

  for (const line of lines) {
    if (!inBlock && line.trim() === "```json") {
      inBlock = true;
      continue;
    }
    if (inBlock && line.trim() === "```") {
      return captured.join("\n").trim();
    }
    if (inBlock) {
      captured.push(line);
    }
  }
  return "";
}

function compactSummary(errors) {
  if (!errors.length) return "";
  const shown = errors.slice(0, 3).join("; ");
  return errors.length > 3 ? `${shown}; +${errors.length - 3} more` : shown;
}

function makeResult(overrides = {}) {
  return {
    ok: false,
    error_kind: "none",
    message: "",
    missing_keys: [],
    type_mismatches: [],
    schema_validation_mode: "off",
    schema_warning: false,
    schema_mismatch_summary: "",
    schema_errors: [],
    ...overrides,
  };
}

function schemaTypeMatches(value, expectedType) {
  if (expectedType === "array") return Array.isArray(value);
  if (expectedType === "null") return value === null;
  if (expectedType === "integer") return Number.isInteger(value);
  if (expectedType === "number") return typeof value === "number" && Number.isFinite(value);
  return typeof value === expectedType;
}

function loadSchema(schemaPath, cache) {
  const absolutePath = path.resolve(schemaPath);
  if (!cache.has(absolutePath)) {
    cache.set(absolutePath, JSON.parse(fs.readFileSync(absolutePath, "utf8")));
  }
  return cache.get(absolutePath);
}

function validateSchema(value, schema, schemaPath, cache, errors, currentPath = "$") {
  if (!schema || typeof schema !== "object") {
    return;
  }

  if (schema.$ref) {
    const refPath = path.resolve(path.dirname(schemaPath), schema.$ref);
    validateSchema(value, loadSchema(refPath, cache), refPath, cache, errors, currentPath);
    return;
  }

  if (Array.isArray(schema.allOf)) {
    for (const child of schema.allOf) {
      validateSchema(value, child, schemaPath, cache, errors, currentPath);
    }
  }

  if (schema.type) {
    const expected = Array.isArray(schema.type) ? schema.type : [schema.type];
    const matches = expected.some((entry) => schemaTypeMatches(value, entry));
    if (!matches) {
      errors.push(`${currentPath}: expected ${expected.join("|")} but got ${typeName(value)}`);
      return;
    }
  }

  if (Array.isArray(schema.enum) && !schema.enum.includes(value)) {
    errors.push(`${currentPath}: expected one of ${schema.enum.join(", ")} but got ${JSON.stringify(value)}`);
  }

  if (schema.type === "object" && value && typeof value === "object" && !Array.isArray(value)) {
    if (Array.isArray(schema.required)) {
      for (const key of schema.required) {
        if (!Object.prototype.hasOwnProperty.call(value, key)) {
          errors.push(`${currentPath}.${key}: missing required property`);
        }
      }
    }
    if (schema.properties && typeof schema.properties === "object") {
      for (const [key, childSchema] of Object.entries(schema.properties)) {
        if (Object.prototype.hasOwnProperty.call(value, key)) {
          validateSchema(value[key], childSchema, schemaPath, cache, errors, `${currentPath}.${key}`);
        }
      }
    }
  }

  if (schema.type === "array" && Array.isArray(value) && schema.items) {
    value.forEach((item, index) => {
      validateSchema(item, schema.items, schemaPath, cache, errors, `${currentPath}[${index}]`);
    });
  }
}

function emitAndExit(result, code) {
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  process.exit(code);
}

try {
  const { bodyFile, schemaFile, disableTypeChecks } = parseArgs(process.argv.slice(2));
  const bodyText = fs.readFileSync(bodyFile, "utf8");
  const jsonBlock = extractJsonBlock(bodyText);

  if (!jsonBlock) {
    emitAndExit(
      makeResult({
        error_kind: "no_json_block",
        message: "response missing required JSON block",
      }),
      10,
    );
  }

  let parsed;
  try {
    parsed = JSON.parse(jsonBlock);
  } catch (error) {
    emitAndExit(
      makeResult({
        error_kind: "invalid_json",
        message: `invalid JSON block: ${error.message}`,
      }),
      11,
    );
  }

  const missingKeys = REQUIRED_KEYS.filter((key) => !Object.prototype.hasOwnProperty.call(parsed, key));
  if (missingKeys.length) {
    emitAndExit(
      makeResult({
        error_kind: "missing_key",
        message: `response JSON missing required key: ${missingKeys[0]}`,
        missing_keys: missingKeys,
      }),
      12,
    );
  }

  if (!disableTypeChecks) {
    const mismatches = [];
    for (const [key, expected] of Object.entries(TYPE_EXPECTATIONS)) {
      const actual = typeName(parsed[key]);
      if (actual !== expected) {
        mismatches.push({ key, expected, actual });
      }
    }
    if (mismatches.length) {
      emitAndExit(
        makeResult({
          error_kind: "type_mismatch",
          message: `response JSON has wrong type for ${mismatches[0].key}: expected ${mismatches[0].expected}, got ${mismatches[0].actual}`,
          type_mismatches: mismatches,
          schema_validation_mode: schemaFile ? "shadow" : "strict",
        }),
        13,
      );
    }
  }

  const result = makeResult({
    ok: true,
    schema_validation_mode: schemaFile ? "shadow" : "strict",
  });

  if (schemaFile) {
    try {
      const cache = new Map();
      const errors = [];
      const absoluteSchemaPath = path.resolve(schemaFile);
      validateSchema(parsed, loadSchema(absoluteSchemaPath, cache), absoluteSchemaPath, cache, errors);
      if (errors.length) {
        result.schema_warning = true;
        result.schema_errors = errors;
        result.schema_mismatch_summary = compactSummary(errors);
      }
    } catch (error) {
      result.schema_warning = true;
      result.schema_errors = [`validator_error: ${error.message}`];
      result.schema_mismatch_summary = result.schema_errors[0];
    }
  }

  emitAndExit(result, 0);
} catch (error) {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exit(1);
}
