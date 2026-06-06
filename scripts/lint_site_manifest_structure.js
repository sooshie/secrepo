#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const manifestPath = process.argv[2] || path.join(process.cwd(), "data", "site-links.json");
const strict = process.argv.includes("--strict");
const raw = fs.readFileSync(manifestPath, "utf8");
const payload = JSON.parse(raw);

const links = Array.isArray(payload.links) ? payload.links : [];
const linkById = new Map(links.map((entry) => [entry.id, entry]));

const issues = [];

function normalizeText(value) {
  return String(value || "")
    .trim()
    .replace(/^[-\u2013\u2014]\s+/, "")
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function linkedDescriptions(parts) {
  const descs = new Set();
  for (const part of parts || []) {
    if (!part || typeof part.link !== "string") continue;
    const entry = linkById.get(part.link);
    const desc = entry && typeof entry.description === "string" ? entry.description.trim() : "";
    if (desc) descs.add(normalizeText(desc));
  }
  return descs;
}

function hasLinkRefs(item) {
  return Array.isArray(item.parts) && item.parts.some((part) => part && typeof part.link === "string");
}

function walkItem(item, pointer) {
  if (!item || typeof item !== "object") return;

  if (Array.isArray(item.license)) {
    issues.push({ level: "error", pointer, rule: "tree-license-present" });
  }

  if (Array.isArray(item.parts)) {
    const descs = linkedDescriptions(item.parts);
    item.parts.forEach((part, idx) => {
      if (!part || typeof part.text !== "string") return;
      const text = part.text;
      if (!/\S/.test(text)) return;

      const norm = normalizeText(text);
      if (norm && descs.has(norm)) {
        issues.push({
          level: "error",
          pointer: `${pointer}.parts[${idx}]`,
          rule: "duplicate-description-text",
          sample: text.trim(),
        });
        return;
      }

      if (hasLinkRefs(item) && /[A-Za-z0-9]/.test(text)) {
        issues.push({
          level: strict ? "error" : "warn",
          pointer: `${pointer}.parts[${idx}]`,
          rule: "inline-content-text",
          sample: text.trim(),
        });
      }
    });
  }

  if (Array.isArray(item.lists)) {
    item.lists.forEach((list, listIdx) => {
      if (!list || !Array.isArray(list.items)) return;
      list.items.forEach((child, childIdx) => {
        walkItem(child, `${pointer}.lists[${listIdx}].items[${childIdx}]`);
      });
    });
  }
}

if (payload.data && Array.isArray(payload.data.groups)) {
  payload.data.groups.forEach((group, gIdx) => {
    if (!group || !Array.isArray(group.categories)) return;
    group.categories.forEach((category, cIdx) => {
      walkItem(category, `data.groups[${gIdx}].categories[${cIdx}]`);
    });
  });
}

if (issues.length === 0) {
  console.log(`OK: ${path.relative(process.cwd(), manifestPath)} passes structure lint`);
  process.exit(0);
}

for (const issue of issues) {
  const sample = issue.sample ? ` :: ${issue.sample}` : "";
  console.log(`${issue.level.toUpperCase()} ${issue.rule} at ${issue.pointer}${sample}`);
}

const hasError = issues.some((i) => i.level === "error");
process.exit(hasError ? 1 : 0);
