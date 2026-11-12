"""
Run once from the Oma-db repo root:   python apply_patches.py
Makes the small edits to existing files (Instagram handle setting + receipt
routes). Safe to run twice: already-applied edits are skipped, and any edit
whose target text is not found is reported instead of guessed.
"""
import pathlib

EDITS = [
    ("app/__init__.py",
     "        app.register_blueprint(api_bp)\n",
     "        app.register_blueprint(api_bp)\n\n"
     "        from app.receipts import receipts_bp\n"
     "        app.register_blueprint(receipts_bp)\n"),

    ("app/models.py",
     "    business_phone = db.Column(db.String(50))\n",
     "    business_phone = db.Column(db.String(50))\n"
     "    instagram_handle = db.Column(db.String(100))\n"),

    ("scripts/repair_runtime_schema.py",
     '    "chat_messages": {\n        "audio_data": "BYTEA",',
     '    "app_settings": {\n        "instagram_handle": "VARCHAR(100)",\n    },\n'
     '    "chat_messages": {\n        "audio_data": "BYTEA",'),

    ("app/api.py",
     "'business_name': s.business_name, 'business_phone': s.business_phone,",
     "'business_name': s.business_name, 'business_phone': s.business_phone,\n"
     "        'instagram_handle': s.instagram_handle,"),
    ("app/api.py",
     "for f in ('business_name','business_phone','business_address','bank_name',",
     "for f in ('business_name','business_phone','instagram_handle','business_address','bank_name',"),

    ("mobile/lib/full_features.dart",
     "  final phone = TextEditingController();\n  final address = TextEditingController();\n  final width = TextEditingController();",
     "  final phone = TextEditingController();\n  final instagram = TextEditingController();\n  final address = TextEditingController();\n  final width = TextEditingController();"),
    ("mobile/lib/full_features.dart",
     "      address.text =\n          '${settings['business_address'] ?? ''}';\n",
     "      instagram.text =\n          '${settings['instagram_handle'] ?? ''}';\n\n      address.text =\n          '${settings['business_address'] ?? ''}';\n"),
    ("mobile/lib/full_features.dart",
     "        'business_address': address.text.trim(),\n        'label_width_mm':",
     "        'instagram_handle': instagram.text.trim(),\n        'business_address': address.text.trim(),\n        'label_width_mm':"),
    ("mobile/lib/full_features.dart",
     "                TextField(\n                  controller: phone,\n                  decoration: const InputDecoration(\n                    labelText: 'Business phone',\n                  ),\n                ),\n                const SizedBox(height: 14),\n",
     "                TextField(\n                  controller: phone,\n                  decoration: const InputDecoration(\n                    labelText: 'Business phone',\n                  ),\n                ),\n                const SizedBox(height: 14),\n"
     "                TextField(\n                  controller: instagram,\n                  decoration: const InputDecoration(\n                    labelText: 'Instagram handle (shown on receipts)',\n                    hintText: '@yourbusiness',\n                  ),\n                ),\n                const SizedBox(height: 14),\n"),
]

done = skipped = failed = 0
for path, old, new in EDITS:
    p = pathlib.Path(path)
    if not p.exists():
        print("MISSING FILE:", path); failed += 1; continue
    text = p.read_text(encoding="utf-8")
    if new in text:
        skipped += 1; continue
    if text.count(old) != 1:
        print(f"NOT APPLIED ({text.count(old)} matches): {path}: {old[:50]!r}"); failed += 1; continue
    p.write_text(text.replace(old, new), encoding="utf-8")
    done += 1
print(f"applied {done}, already done {skipped}, problems {failed}")
