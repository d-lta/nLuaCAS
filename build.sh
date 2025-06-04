#!/bin/zsh

FILES=(
  "src/ast.lua"
  "src/parser.lua"
  "src/simplify.lua"
  "src/trig.lua"
  
  "src/derivative.lua"
  "src/integrate.lua"
  "src/solve.lua"
  "src/factorial.lua"
  "src/gui.lua"
)

OUT="build.lua"

echo "--[[ This file is auto-generated. Do not edit directly. ]]" > "$OUT"

for f in $FILES; do
  echo "-- Begin $f" >> "$OUT"

  # Always strip 'require' lines, but keep return statements
  if [[ -f "$f" ]]; then
    grep -vE '^\s*require\(' "$f" >> "$OUT"
  else
    echo "Missing file: $f" >&2
    exit 1
  fi

  printf "\n-- End %s\n\n" "$f" >> "$OUT"
done

echo "Build complete: $OUT"