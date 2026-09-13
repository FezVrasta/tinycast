import type { IconName } from "../components/ui/feature-icons";

export type Feature = {
  icon: IconName;
  title: string;
  body: string;
  /** Deep link into the docs page that covers this feature. */
  href: string;
  // `wide` features span two columns in the bento grid.
  wide?: boolean;
};

// Everything Tinycast does, in plain language. Kept true to what the app
// actually ships — each maps to a real feature in the source, and each links
// to the docs page that covers it.
export const features: Feature[] = [
  {
    icon: "launch",
    title: "App launcher",
    body: "Fuzzy-search every app on your Mac and open it with a keystroke. Pin the ones you reach for, see what's already running, and restart or quit an app without leaving the keyboard.",
    href: "/docs/launcher",
    wide: true,
  },
  {
    icon: "aiChat",
    title: "AI Chat",
    body: "Ask Apple Intelligence on your Mac, the Codex, Claude or OpenCode you already use, or any API you bring. Keys stay in your Keychain.",
    href: "/docs/ai",
  },
  {
    icon: "extensions",
    title: "Extensions",
    body: "Runs Raycast extensions natively, rendered as SwiftUI. Install from the store without a toolchain, or bring over the ones you already have.",
    href: "/docs/extensions",
  },
  {
    icon: "clipboard",
    title: "Clipboard history",
    body: "Text, images, files and colors, searchable even inside screenshots, filtered by type, and pasted straight back where you came from.",
    href: "/docs/features/clipboard",
  },
  {
    icon: "quickActions",
    title: "Quick Actions",
    body: "Select text in any app and press a key to fix, rewrite, translate or summarize it. Add your own prompts too.",
    href: "/docs/ai/quick-actions",
  },
  {
    icon: "calculator",
    title: "Inline calculator",
    body: "Math, units, live currency and crypto, time zones and plain-English dates like “days till 9 Apr”, right in the palette.",
    href: "/docs/features/calculator",
  },
  {
    icon: "snippets",
    title: "Snippets",
    body: "Reusable Markdown templates with placeholders, arguments and nested references. Type a keyword in any app and it expands.",
    href: "/docs/features/snippets",
  },
  {
    icon: "notes",
    title: "Floating notes",
    body: "Plain Markdown files in one floating editor. No database, no frontmatter. The file on disk is exactly what you typed.",
    href: "/docs/features/notes",
  },
  {
    icon: "fileSearch",
    title: "File search",
    body: "Find files and folders through the Spotlight index, with a preview and Quick Look. Needs no file permission at all.",
    href: "/docs/features/file-search",
  },
  {
    icon: "calendar",
    title: "Calendar & meetings",
    body: "Join the next Zoom, Meet or Teams call with one key, see your day, and keep the next event in the menu bar.",
    href: "/docs/features/calendar",
  },
  {
    icon: "windows",
    title: "Window management",
    body: "Halves, thirds, nudges, display moves and instant Space switching. 34 commands, plus saved layouts, with no new permission.",
    href: "/docs/features/window-management",
  },
  {
    icon: "navigation",
    title: "Window & menu search",
    body: "Jump to any open window, or press any item in the front app's menu bar, just by typing its name.",
    href: "/docs/features/navigation",
  },
  {
    icon: "quicklinks",
    title: "Quicklinks",
    body: "Turn a URL, search, file or deeplink into a real command, with values you fill in right in the search bar.",
    href: "/docs/launcher/quicklinks",
  },
  {
    icon: "keyboard",
    title: "Custom commands",
    body: "Name a shell command, ask for arguments, watch its output live, and run it from search or its own hotkey.",
    href: "/docs/launcher/commands",
  },
  {
    icon: "bolt",
    title: "System actions",
    body: "Lock, sleep, restart, volume, Bluetooth, Stage Manager, empty the Trash. 31 actions, each bindable to a key.",
    href: "/docs/launcher/system-actions",
  },
  {
    icon: "emoji",
    title: "Emoji & symbols",
    body: "Search the full emoji and symbol set, tune the skin tone, and your most-used ones float to the top.",
    href: "/docs/features/emoji",
  },
  {
    icon: "globe",
    title: "Global & per-app hotkeys",
    body: "Record a shortcut to summon the palette, bind a key to any app to focus or hide it, or double-tap a lone modifier.",
    href: "/docs/reference/hotkeys",
  },
  {
    icon: "hyper",
    title: "Hyper key",
    body: "Turn Caps Lock or a right-side modifier into ⌃⌥⇧⌘. A whole extra layer of shortcuts, shown as a single ✦.",
    href: "/docs/reference/hotkeys",
  },
  {
    icon: "alias",
    title: "Aliases",
    body: "Rename anything in the launcher. Type an alias exactly and it wins, so “ps” can open Photoshop.",
    href: "/docs/launcher/aliases",
  },
  {
    icon: "uninstall",
    title: "App uninstaller",
    body: "Remove an app and the caches, preferences and containers it leaves behind. Everything goes to the Trash, never deleted.",
    href: "/docs/launcher/uninstall",
  },
  {
    icon: "inputSource",
    title: "Input source switching",
    body: "Switch the keyboard to a chosen source while the palette is open, and put it back when you leave.",
    href: "/docs/palette#input-source",
  },
  {
    icon: "appearance",
    title: "Make it yours",
    body: "Light or Dark, a larger interface, and as much glass as you like. Same design either way.",
    href: "/docs/palette#appearance",
  },
  {
    icon: "backup",
    title: "Backup & restore",
    body: "Export your shortcuts, favorites, clips, snippets and notes to one file, then restore it on another Mac. A backup can never grant a permission.",
    href: "/docs/reference/backup",
  },
];
