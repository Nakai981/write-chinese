"""Refresh the bundled HSK vocabulary from the attributed upstream CSV."""
import csv
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
with (root / 'assets/hsk_words.csv').open(encoding='utf-8-sig', newline='') as source:
    words = list(csv.DictReader(source))
(root / 'assets/words.json').write_text(json.dumps(words, ensure_ascii=False), encoding='utf-8')
print(f'Prepared {len(words)} HSK words')
