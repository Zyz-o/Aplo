# Third-party notices

Aplo includes source code from LaunchNext by RoversX and contributors, based on LaunchNow by ggkevinnnn and contributors.

Upstream: https://github.com/RoversX/LaunchNext
Revision: d3dd4a39335bc7d46f01545692cd672e7e1ee0e2
License: GNU General Public License version 3 (see LICENSE).

The following files originate from LaunchNext/LaunchNext/Search:
- Sources/Vendor/LaunchNextSearch/FuzzyMatcher.swift
- Sources/Vendor/LaunchNextSearch/SearchIndexEntry.swift
- Sources/Vendor/LaunchNextSearch/CJKTransliterator.swift

SearchIndexEntry.swift and CJKTransliterator.swift are unmodified. FuzzyMatcher.swift adds a prepared-query scoring entry point in Aplo 3.12.0 to reuse query normalization; the original entry point and scoring behavior are retained.

Aplo's integration adapter and presentation modes are local additions. Aplo is distributed under GPL version 3. The installed app includes LICENSE, this notice, and CorrespondingSource.zip in Contents/Resources, containing the sources, assets and scripts used to build it. No warranty is provided; see the license for details.

Version 3.2 additionally adapts LaunchNext/LaunchNext/SoundManager.swift into Sources/Vendor/LaunchNextSound/SoundManager.swift. Changes: bind to LauncherModel preferences, remove voice-feedback dependency, add per-app volume and navigation-event throttling, and annotate MainActor isolation. The upstream GPL-3.0 license and attribution apply.
