#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const manifestPath = process.argv[2] || path.join(process.cwd(), "data", "site-links.json");
const raw = fs.readFileSync(manifestPath, "utf8");
const payload = JSON.parse(raw);

const links = Array.isArray(payload.links) ? payload.links : [];
const linkById = new Map(links.map((entry) => [entry.id, entry]));

let removedDuplicateTextParts = 0;
let removedTreeLicenses = 0;

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

function isDuplicateDescriptionText(textValue, partDescriptions) {
  const norm = normalizeText(textValue);
  if (!norm) return false;
  return partDescriptions.has(norm);
}

function walkItem(item) {
  if (!item || typeof item !== "object") return;

  if (Array.isArray(item.license)) {
    delete item.license;
    removedTreeLicenses += 1;
  }

  if (Array.isArray(item.parts)) {
    const descs = linkedDescriptions(item.parts);
    if (descs.size > 0) {
      item.parts = item.parts.filter((part) => {
        if (!part || typeof part.text !== "string") return true;
        if (!isDuplicateDescriptionText(part.text, descs)) return true;
        removedDuplicateTextParts += 1;
        return false;
      });
    }
  }

  if (Array.isArray(item.lists)) {
    for (const list of item.lists) {
      if (!list || !Array.isArray(list.items)) continue;
      for (const child of list.items) walkItem(child);
    }
  }
}

if (payload.data && Array.isArray(payload.data.groups)) {
  for (const group of payload.data.groups) {
    if (!group || !Array.isArray(group.categories)) continue;
    for (const category of group.categories) {
      walkItem(category);
      if (!Array.isArray(category.lists)) continue;
      for (const list of category.lists) {
        if (!list || !Array.isArray(list.items)) continue;
        for (const item of list.items) walkItem(item);
      }
    }
  }
}

fs.writeFileSync(manifestPath, JSON.stringify(payload, null, 2) + "\n", "utf8");
console.log(
  `normalized ${path.relative(process.cwd(), manifestPath)}: removed ${removedDuplicateTextParts} duplicate text part(s), removed ${removedTreeLicenses} tree license block(s)`
);
