# Release applet template

Adapted directly from `Carnet de Recettes/Release/CarnetRelease/main.swift` on 2026-10-26 at Max’s request. The original window, header, segmented tabs, grouped forms, controls, progress panel and log layout are retained. Only project names, paths, copy about capabilities, and backend commands change.

The applet's Finder/Dock icon uses PocketMe's approved taupe pocket artwork at Max's request; its window layout remains the Carnet template.

The release applet is a separate developer tool: keep its Carnet template UI, even though the PocketMe product uses its own design system. Do not restyle it or add a new UI.

The applet supports local Dev builds, tests, device installation, and unsigned Mac/iOS archives. TestFlight uploads and publishing are blocked until M7 sets up PocketMe’s own signing, App Store listing, icons and distribution. No Carnet credentials, release folders or release scripts are used.
