# PickleBlast Privacy

This notice describes the behavior of the PickleBlast application in the inspected development candidate. It does not describe Apple's operating system services or any future website or support service.

## Information stored by the app

PickleBlast stores Digital Crown sensitivity, the haptics preference, the best Arcade score, and records for The Wall, The Banger, and The Poacher in the app's local UserDefaults storage. A match in progress is held in memory and is not restored after the app process ends.

The app works offline. Its application code does not create accounts, send gameplay information to a server, include analytics or advertising integrations, track users, or access health, location, contacts, microphone, or camera information.

## Managing local information

You can change Crown sensitivity and haptics in Settings. There is no in-app control to erase saved records. Deleting the app removes its local data container; Apple's backup and restore services may retain or restore app data under Apple's policies. PickleBlast does not keep a remote copy of these settings or records.

Apple may process information through its operating system, backups, diagnostics, development installation, or future distribution services under Apple's own policies. This notice makes no claim about Apple's collection or processing.

The source includes a privacy manifest declaring no collected data or tracking and describing app-owned UserDefaults access. Review the exact distribution build and its privacy declarations before release.
