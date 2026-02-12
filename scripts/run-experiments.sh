#!/bin/bash
# run-experiments.sh — Validate curl-based GitHub installer for Tinderbox
#
# Requires: Tinderbox running with a document open.
# Tests that runCommand("curl ...") can fetch installer components from GitHub.
#
# Run: bash scripts/run-experiments.sh

set -e

PASS=0
FAIL=0
TESTS=()

pass() {
  PASS=$((PASS + 1))
  TESTS+=("{\"test\": \"$1\", \"status\": \"pass\"}")
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  TESTS+=("{\"test\": \"$1\", \"status\": \"fail\", \"detail\": \"$2\"}")
  echo "  FAIL: $1 — $2"
}

BASE_URL="https://raw.githubusercontent.com/jacobio/tbx-notetaker/main"

# Write preamble to temp file — avoids bash quoting issues with ! in if(!path)
PREAMBLE_FILE=$(mktemp /tmp/tbx-preamble.XXXXXXXX)
cat > "$PREAMBLE_FILE" <<'PREAMBLE_EOF'
function getTinderbox() {
  var app = Application.currentApplication();
  app.includeStandardAdditions = true;
  var path = app.doShellScript("ls -d /Applications/Tinderbox*.app 2>/dev/null | head -1");
  if (!path) throw new Error("Tinderbox not found in /Applications");
  return Application(path);
}
var Tbx = getTinderbox();
PREAMBLE_EOF
echo "var BASE_URL = \"${BASE_URL}\";" >> "$PREAMBLE_FILE"

# Helper: run JXA with preamble prepended
run_jxa() {
  { cat "$PREAMBLE_FILE"; cat; } | osascript -l JavaScript 2>/dev/null
}

cleanup_temp() {
  rm -f "$PREAMBLE_FILE"
}
trap cleanup_temp EXIT

echo "GitHub Installer Experiments"
echo "============================"
echo ""

# -----------------------------------------------------------------------
# Setup: Create test container
# -----------------------------------------------------------------------
echo "Setup: Creating test container..."
RESULT=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = Tbx.make({new: "note", at: doc, withProperties: {name: "__CURL_TEST_ROOT__"}});
  JSON.stringify({success: true});
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

if ! echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success']" 2>/dev/null; then
  echo "FATAL: Could not create test container: $RESULT"
  exit 1
fi
echo ""

# -----------------------------------------------------------------------
# Experiment 1: Basic curl — fetch hello.txt, verify content
# -----------------------------------------------------------------------
echo "Experiment 1: Basic curl fetch"
RESULT=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");

  // Create test note
  root.actOn({with: 'create("Exp1-Curl")'});
  var child = root.notes.byName("Exp1-Curl");

  var text = "";
  var method = "";

  // Try: curl -s
  child.actOn({with: '$Text = runCommand("curl -s ' + BASE_URL + '/test-data/hello.txt")'});
  text = child.evaluate({with: "$Text"});
  if (text.indexOf("Hello from GitHub") >= 0) {
    method = "curl -s";
  } else {
    // Try: /usr/bin/curl -s
    child.actOn({with: '$Text = runCommand("/usr/bin/curl -s ' + BASE_URL + '/test-data/hello.txt")'});
    text = child.evaluate({with: "$Text"});
    if (text.indexOf("Hello from GitHub") >= 0) {
      method = "/usr/bin/curl -s";
    } else {
      // Try: /usr/bin/curl -sL (follow redirects)
      child.actOn({with: '$Text = runCommand("/usr/bin/curl -sL ' + BASE_URL + '/test-data/hello.txt")'});
      text = child.evaluate({with: "$Text"});
      if (text.indexOf("Hello from GitHub") >= 0) {
        method = "/usr/bin/curl -sL";
      }
    }
  }

  JSON.stringify({
    success: true,
    text: text,
    match: (text.indexOf("Hello from GitHub") >= 0),
    method: method
  });
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d['match']" 2>/dev/null; then
  METHOD=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('method',''))" 2>/dev/null)
  pass "Basic curl fetch (via $METHOD)"
else
  fail "Basic curl fetch" "$RESULT"
fi

# -----------------------------------------------------------------------
# Experiment 2: Library function — fetch utils.txt, compile, call now()
# -----------------------------------------------------------------------
echo "Experiment 2: Library function"
RESULT=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");

  // Create library note
  root.actOn({with: 'create("Exp2-Utils")'});
  var lib = root.notes.byName("Exp2-Utils");

  // Fetch utils.txt via curl and set as action
  lib.actOn({with: '$IsAction = true'});
  lib.actOn({with: '$Text = runCommand("curl -s ' + BASE_URL + '/library/utils.txt")'});

  // Verify text was fetched
  var text = lib.evaluate({with: "$Text"});
  var hasFunctionDef = (text.indexOf("function now()") >= 0);

  // Compile the library
  var libPath = lib.evaluate({with: "$Path"});
  root.actOn({with: 'update("' + libPath + '")'});

  // Test: call now() which is defined in utils.txt
  var result = root.evaluate({with: "now()"});

  JSON.stringify({
    success: true,
    hasFunctionDef: hasFunctionDef,
    nowResult: result,
    hasResult: (result.length > 0)
  });
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d['hasResult']" 2>/dev/null; then
  TIMESTAMP=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('nowResult',''))" 2>/dev/null)
  pass "Library function (now() = $TIMESTAMP)"
else
  fail "Library function" "$RESULT"
fi

# -----------------------------------------------------------------------
# Experiment 3: Bootstrap action() — fetch and execute action code via curl
# -----------------------------------------------------------------------
echo "Experiment 3: Bootstrap action()"
RESULT=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");

  // Create test note
  root.actOn({with: 'create("Exp3-Bootstrap")'});
  var child = root.notes.byName("Exp3-Bootstrap");

  // Bootstrap: fetch action code via curl and execute it
  child.actOn({with: 'action(runCommand("curl -s ' + BASE_URL + '/test-data/test-action.txt"))'});

  // Verify the note was renamed and recolored
  var renamedExists = false;
  var newColor = "";
  try {
    var renamed = root.notes.byName("curl-bootstrap-success");
    renamedExists = true;
    newColor = renamed.evaluate({with: "$Color"});
  } catch(e) {}

  JSON.stringify({
    success: true,
    renamedExists: renamedExists,
    newColor: newColor
  });
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d['renamedExists']" 2>/dev/null; then
  COLOR=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('newColor',''))" 2>/dev/null)
  pass "Bootstrap action() (color=$COLOR)"
else
  fail "Bootstrap action()" "$RESULT"
fi

# -----------------------------------------------------------------------
# Experiment 4: Quoted expressions — $DisplayExpression and $OnAdd via curl
# -----------------------------------------------------------------------
echo "Experiment 4: Quoted expressions"
RESULT=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");

  // Create user attribute for test
  root.actOn({with: 'createAttribute("OutlineDesignator", "string")'});

  // Create test note
  root.actOn({with: 'create("Exp4-Expressions")'});
  var child = root.notes.byName("Exp4-Expressions");

  // Set OutlineDesignator value
  child.actOn({with: '$OutlineDesignator = "I."'});

  // Fetch and set $DisplayExpression via curl
  child.actOn({with: '$DisplayExpression = runCommand("curl -s ' + BASE_URL + '/expressions/display-expression.txt").trim'});

  // Read back the expression and evaluate it
  var displayExpr = child.evaluate({with: "$DisplayExpression"});
  var displayName = child.evaluate({with: "$DisplayName"});

  // Fetch and set $OnAdd via curl
  child.actOn({with: '$OnAdd = runCommand("curl -s ' + BASE_URL + '/expressions/onadd.txt").trim'});

  // Read back $OnAdd
  var onAdd = child.evaluate({with: "$OnAdd"});

  JSON.stringify({
    success: true,
    displayExpr: displayExpr,
    displayName: displayName,
    onAdd: onAdd,
    displayExprHasDollar: (displayExpr.indexOf("$") >= 0),
    displayNameCorrect: (displayName.indexOf("I.") >= 0 && displayName.indexOf("Exp4") >= 0),
    onAddHasPrototype: (onAdd.indexOf("Prototype") >= 0)
  });
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d['displayExprHasDollar'] and d['onAddHasPrototype']" 2>/dev/null; then
  DISPLAY=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('displayName',''))" 2>/dev/null)
  pass "Quoted expressions (DisplayName=$DISPLAY)"
else
  fail "Quoted expressions" "$RESULT"
fi

# -----------------------------------------------------------------------
# Cleanup: Delete test container and all children
# -----------------------------------------------------------------------
echo ""
echo "Cleanup: Removing test notes..."
RESULT=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var deleted = [];

  // Delete test root (recursively deletes children)
  try {
    var root = doc.notes.byName("__CURL_TEST_ROOT__");
    Tbx.delete(root);
    deleted.push("__CURL_TEST_ROOT__");
  } catch(e) {}

  JSON.stringify({success: true, deleted: deleted});
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success']" 2>/dev/null; then
  echo "  Cleanup complete"
else
  echo "  Cleanup warning: $RESULT"
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "============================"
echo "Results: $PASS passed, $FAIL failed out of $((PASS + FAIL)) experiments"
echo ""

# JSON summary
TESTS_JSON=$(IFS=,; echo "${TESTS[*]}")
echo "{\"passed\": $PASS, \"failed\": $FAIL, \"total\": $((PASS + FAIL)), \"tests\": [$TESTS_JSON]}"
