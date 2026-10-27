#!/bin/zsh
set -eu
cd "${0:A:h:h}"
swiftc Search.swift CaptionDetector.swift tests/main.swift -o tests/search-checks -framework NaturalLanguage -framework PDFKit -framework CoreText
./tests/search-checks
swiftc BalancedSplitView.swift tests/layout/main.swift -o tests/layout-checks -framework AppKit
./tests/layout-checks
swiftc HighlightStore.swift tests/highlights/main.swift -o tests/highlight-checks -framework AppKit -framework PDFKit -framework CoreText
./tests/highlight-checks
