// Drives the "Import your setup" block. The steps mirror the real import flow
// (Settings → Backup → Raycast Export), and `transfers` matches the app's
// `RaycastImportOptions` exactly — don't add anything the importer can't carry.

export const migration = {
  eyebrow: "Already set up elsewhere?",
  title: "Bring your setup with you.",
  intro:
    "Tinycast reads a Raycast export directly. Point it at your .rayconfig file, type the passphrase, and pick what comes across — no redoing shortcuts by hand.",
  steps: [
    {
      title: "Export what you have",
      body: "In Raycast, export your settings and data, and note the passphrase.",
    },
    {
      title: "Open Settings → Backup",
      body: "Choose the file, then type the passphrase. A wrong one is reported as exactly that.",
    },
    {
      title: "Pick what to bring",
      body: "Keep it all or just the parts you want — then you're set up.",
    },
  ],
  // Must match RaycastImportOptions in Features/Backup/Model/RaycastImport.swift.
  transfers: [
    "Shortcuts",
    "Favorites",
    "Clipboard history",
    "Snippets",
    "Quicklinks",
    "Aliases",
    "Emoji skin tone",
    "Compact mode",
    "Pop to root",
    "Launch at login",
    "Menu-bar preference",
  ],
} as const;
