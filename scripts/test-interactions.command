#!/bin/zsh
set -eu
cd "${0:A:h:h}"
interaction_test_dir=$(mktemp -d "${TMPDIR:-/tmp}/paper-reader-interactions.XXXXXX")
trap 'rm -rf "$interaction_test_dir"' EXIT
# Compile the real Reader without starting the app/event loop. The tests use
# generated PDFs and invoke its actual search and gesture handlers.
python3 - "$interaction_test_dir/Reader.swift" <<'PY'
import sys
from pathlib import Path
source = Path('main.swift').read_text()
Path(sys.argv[1]).write_text(source[:source.rindex('let app = NSApplication.shared')])
PY
swiftc "$interaction_test_dir/Reader.swift" Search.swift CaptionDetector.swift BalancedSplitView.swift HighlightStore.swift SelectionPDFView.swift tests/interactions/main.swift -o "$interaction_test_dir/checks" -framework AppKit -framework PDFKit -framework NaturalLanguage -framework CoreText
"$interaction_test_dir/checks"
