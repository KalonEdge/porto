---
title: Change Porto’s language
description: Porto’s Mac app is available in eight languages. Choose one during onboarding, switch in Settings → General → Language, set it with porto language, or let Porto follow your Mac’s preferred languages.
published: 2026-09-29
updated: 2026-09-29
order: 10
keywords: Porto language, change Porto language, Porto Japanese, Porto German, Porto French, Porto Spanish, Porto Simplified Chinese, Porto Hebrew, Porto Ukrainian, porto language command, mac menu bar app language
---

You can use Porto in English, German, French, Spanish, Simplified Chinese, Hebrew, Japanese or Ukrainian. The choice is offered the first time Porto opens, lives in Settings afterwards, can be scripted from the terminal, and can be left to your Mac with System default. Whichever way you change it in the app, it takes effect immediately, without a restart.

## Languages and their codes

| Language | Code for `porto language` |
| --- | --- |
| English | `en` |
| German (Deutsch) | `de` |
| French (Français) | `fr` |
| Spanish (Español) | `es` |
| Simplified Chinese (简体中文) | `zh-Hans` |
| Hebrew (עברית) | `he` |
| Japanese (日本語) | `ja` |
| Ukrainian (Українська) | `uk` |
| System default, following your Mac | `system` |

The `system` code does the same as choosing System default in the app.

## Choose it on first launch

The language picker is on the very first onboarding screen. Whatever you choose there applies to the rest of setup straight away, including the step that offers to install the `porto` command for the terminal.

## Change it in Settings

Right-click the Porto icon in the menu bar, choose Settings…, then open General → Language. Pick a language and Porto switches to it immediately. There is nothing to quit or reopen, and the servers Porto is watching carry on as before.

## Let Porto follow your Mac

System default uses your Mac’s preferred languages, the ordered list in System Settings → General → Language & Region. Porto matches that list against its eight languages and falls back to English when none of them match. To see the list from the terminal:

```bash
defaults read -g AppleLanguages
```

```text
(
    "uk-UA",
    "en-US"
)
```

With a list like this one, Porto appears in Ukrainian. System default is the natural choice if you already run your Mac in the language you want Porto to use.

## From the terminal: porto language

Once the `porto` command is installed, you can read and change the language without opening Settings. Install it from onboarding, or from Settings → General → Terminal, which links `/usr/local/bin/porto` to the app’s executable. Then:

```bash
porto language
porto language ja
porto language system
```

The first shows the current setting, the second switches Porto to Japanese, and the third goes back to following your Mac. Any code from the table works. Setting it from the terminal is handy in a dotfiles repository or a script that sets up a new Mac.

If you skipped the install step and `porto` isn’t found, you can create the link yourself:

```bash
sudo ln -sf /Applications/Porto.app/Contents/MacOS/Porto /usr/local/bin/porto
```

## What stays in English

The terminal side of Porto is English on purpose, whatever language the app is in:

- the terminal UI that opens when you run `porto`,
- the command help,
- the JSON from `porto list --json`.

That keeps scripts, agents and anything else that reads Porto’s output working when someone changes the app language. Field names such as `memoryBytes` and status values such as `running`, `attention` and `idle` don’t change with the language.

Your own data isn’t translated either. Project names, git branches and folder paths appear exactly as they are on disk.

## Right-to-left layout for Hebrew

Hebrew is written right to left, and choosing it switches Porto’s interface to a right-to-left layout rather than simply translating the labels.

## Spotted a translation that reads oddly?

If a label is wrong, awkward or too long for its space, right-click the menu bar icon and choose Send Feedback. Mention the language and where the text appears.

## New to Porto?

Porto is a free, open-source menu bar app that shows every dev server running on your Mac, with its port, project, git branch, memory and CPU. [Download Porto](/Porto.dmg), or start with [how to see every dev server running on your Mac](/guides/see-every-dev-server-running-on-mac).
