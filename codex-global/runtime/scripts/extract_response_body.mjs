#!/usr/bin/env node

import fs from "node:fs";

const [, , inputPath, outputPath] = process.argv;

if (!inputPath || !outputPath) {
  console.error("Usage: node scripts/extract_response_body.mjs <input> <output>");
  process.exit(1);
}

const raw = fs.readFileSync(inputPath, "utf8");

function pickText(value) {
  if (typeof value === "string" && value.trim()) {
    return value;
  }

  if (!value || typeof value !== "object") {
    return "";
  }

  const directKeys = ["result", "content", "response", "text", "message", "output"];
  for (const key of directKeys) {
    const candidate = value[key];
    if (typeof candidate === "string" && candidate.trim()) {
      return candidate;
    }
  }

  if (Array.isArray(value)) {
    for (const item of value) {
      const nested = pickText(item);
      if (nested) {
        return nested;
      }
    }
  }

  for (const nestedValue of Object.values(value)) {
    const nested = pickText(nestedValue);
    if (nested) {
      return nested;
    }
  }

  return "";
}

let body = raw;
try {
  const parsed = JSON.parse(raw);
  const extracted = pickText(parsed);
  if (extracted) {
    body = extracted;
  }
} catch {
  body = raw;
}

fs.writeFileSync(outputPath, body, "utf8");
