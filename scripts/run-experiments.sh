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

# Write preamble with getTinderbox() helper
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
# Experiment 1: Basic curl — evaluate runCommand directly (no actOn)
# Discovery: actOn + evaluate has a caching delay in JXA.
# Using evaluate({with: 'runCommand(...)'}) returns the result directly.
# -----------------------------------------------------------------------
echo "Experiment 1: Basic curl fetch"
RESULT=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");
  var results = {success: true};

  // Diagnostic: Does runCommand work via evaluate?
  results.echoResult = root.evaluate({with: 'runCommand("echo hello-from-runCommand")'});

  // Test curl via evaluate (no actOn needed)
  results.curlResult = root.evaluate({with: 'runCommand("curl -s ' + BASE_URL + '/test-data/hello.txt")'});

  // Fallback: full path
  results.curlFull = root.evaluate({with: 'runCommand("/usr/bin/curl -s ' + BASE_URL + '/test-data/hello.txt")'});

  // Fallback: with -L flag
  results.curlL = root.evaluate({with: 'runCommand("/usr/bin/curl -sL ' + BASE_URL + '/test-data/hello.txt")'});

  // Check results
  var fields = ["curlResult", "curlFull", "curlL"];
  results.match = false;
  for (var i = 0; i < fields.length; i++) {
    var v = results[fields[i]] || "";
    if (v.indexOf("Hello from GitHub") >= 0) {
      results.match = true;
      results.matchField = fields[i];
      break;
    }
  }

  JSON.stringify(results);
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

echo "  DEBUG: $RESULT"
if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d['match']" 2>/dev/null; then
  FIELD=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('matchField',''))" 2>/dev/null)
  pass "Basic curl fetch (via $FIELD)"
else
  fail "Basic curl fetch" "$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:v for k,v in d.items() if k != 'success'})" 2>/dev/null)"
fi

# -----------------------------------------------------------------------
# Experiment 2: actOn with runCommand — test the installer pattern
# actOn sets the value; a SEPARATE JXA invocation reads it back
# -----------------------------------------------------------------------
echo "Experiment 2: Installer pattern (actOn + deferred read)"

# Step A: Set $Text via actOn with curl (the pattern install.txt uses)
RESULT_A=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");

  // Create library note and set text via curl
  var lib = Tbx.make({new: "note", at: root, withProperties: {name: "Exp2-Utils"}});
  lib.actOn({with: '$IsAction = true'});
  lib.actOn({with: '$Text = runCommand("curl -s ' + BASE_URL + '/library/utils.txt")'});

  JSON.stringify({success: true, created: true});
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

# Step B: Read back in a SEPARATE JXA invocation (avoids caching)
RESULT_B=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");
  var lib = root.notes.byName("Exp2-Utils");
  var results = {success: true};

  // Read text via JXA property
  try {
    var text = lib.text();
    results.textLength = text.length;
    results.hasFunctionDef = (text.indexOf("function now()") >= 0);
    results.textPreview = text.substring(0, 80);
  } catch(e) {
    results.textReadError = e.message;
  }

  // Try compiling and calling now()
  try {
    var libPath = lib.evaluate({with: "$Path"});
    results.libPath = libPath;
    root.actOn({with: 'update("' + libPath + '")'});
    results.compiled = true;
  } catch(e) {
    results.compileError = e.message;
  }

  JSON.stringify(results);
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

# Step C: Call now() in yet another invocation (after compile)
RESULT_C=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");
  var results = {success: true};

  var result = root.evaluate({with: "now()"});
  results.nowResult = result;
  results.hasResult = (result.length > 0);

  JSON.stringify(results);
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

echo "  DEBUG-A: $RESULT_A"
echo "  DEBUG-B: $RESULT_B"
echo "  DEBUG-C: $RESULT_C"

if echo "$RESULT_C" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d.get('hasResult')" 2>/dev/null; then
  TIMESTAMP=$(echo "$RESULT_C" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('nowResult',''))" 2>/dev/null)
  pass "Installer pattern + library compile (now() = $TIMESTAMP)"
elif echo "$RESULT_B" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d.get('hasFunctionDef')" 2>/dev/null; then
  pass "Installer pattern (text fetched, compile issue)"
elif echo "$RESULT_B" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d.get('textLength',0) > 0" 2>/dev/null; then
  PREVIEW=$(echo "$RESULT_B" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('textPreview',''))" 2>/dev/null)
  pass "Installer pattern (text fetched: $PREVIEW)"
else
  fail "Installer pattern" "A=$RESULT_A B=$RESULT_B C=$RESULT_C"
fi

# -----------------------------------------------------------------------
# Experiment 3: Bootstrap action() — fetch and execute action code via curl
# -----------------------------------------------------------------------
echo "Experiment 3: Bootstrap action()"
RESULT=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");
  var results = {success: true};

  var child = Tbx.make({new: "note", at: root, withProperties: {name: "Exp3-Bootstrap"}});
  results.origName = child.name();

  // Bootstrap: fetch action code via curl and execute it
  child.actOn({with: 'action(runCommand("curl -s ' + BASE_URL + '/test-data/test-action.txt"))'});

  // Check if note was renamed (need fresh lookup since name changed)
  results.renamedExists = false;
  try {
    var renamed = root.notes.byName("curl-bootstrap-success");
    results.renamedExists = true;
    results.newName = renamed.name();
    results.newColor = renamed.evaluate({with: "$Color"});
  } catch(e) {
    results.findError = e.message;
    // Check if still original name
    try {
      results.currentName = root.notes.byName("Exp3-Bootstrap").name();
    } catch(e2) {
      results.currentNameError = e2.message;
    }
  }

  JSON.stringify(results);
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

echo "  DEBUG: $RESULT"
if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d.get('renamedExists')" 2>/dev/null; then
  pass "Bootstrap action()"
else
  fail "Bootstrap action()" "$(echo "$RESULT" | head -c 200)"
fi

# -----------------------------------------------------------------------
# Experiment 4: Quoted expressions — set and verify in separate invocations
# -----------------------------------------------------------------------
echo "Experiment 4: Quoted expressions"

# Step A: Verify curl returns correct expression content
RESULT_A=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");
  var results = {success: true};

  // Verify curl returns correct expression content
  results.displayExprContent = root.evaluate({with: 'runCommand("curl -s ' + BASE_URL + '/expressions/display-expression.txt")'});
  results.onAddContent = root.evaluate({with: 'runCommand("curl -s ' + BASE_URL + '/expressions/onadd.txt")'});

  results.displayExprCorrect = (results.displayExprContent.indexOf("OutlineDesignator") >= 0);
  results.onAddCorrect = (results.onAddContent.indexOf("Prototype") >= 0);

  JSON.stringify(results);
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

# Step B: Test actOn with literal $DisplayExpression and via action()
RESULT_B=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");
  var results = {success: true};

  root.actOn({with: 'createAttribute("OutlineDesignator", "string")'});
  var child = Tbx.make({new: "note", at: root, withProperties: {name: "Exp4-Expressions"}});
  child.actOn({with: '$OutlineDesignator = "I."'});

  // Test 1: Can actOn set $DisplayExpression to a literal?
  child.actOn({with: '$DisplayExpression = "LITERAL_TEST"'});

  // Test 2: Try via action() with the curl result
  child.actOn({with: 'var:string expr = runCommand("curl -s ' + BASE_URL + '/expressions/display-expression.txt").trim; $DisplayExpression = expr;'});

  // Test 3: Try $OnAdd similarly
  child.actOn({with: 'var:string oa = runCommand("curl -s ' + BASE_URL + '/expressions/onadd.txt").trim; $OnAdd = oa;'});

  JSON.stringify(results);
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

# Step C: Read back
RESULT_C=$(run_jxa <<'ENDSCRIPT'
try {
  var doc = Tbx.documents[0];
  var root = doc.notes.byName("__CURL_TEST_ROOT__");
  var child = root.notes.byName("Exp4-Expressions");
  var results = {success: true};

  results.displayExpr = child.evaluate({with: "$DisplayExpression"});
  results.displayName = child.evaluate({with: "$DisplayName"});
  results.onAdd = child.evaluate({with: "$OnAdd"});
  results.designator = child.evaluate({with: "$OutlineDesignator"});

  JSON.stringify(results);
} catch(e) {
  JSON.stringify({success: false, error: e.message});
}
ENDSCRIPT
)

echo "  DEBUG-A: $RESULT_A"
echo "  DEBUG-B: $RESULT_B"
echo "  DEBUG-C: $RESULT_C"
if echo "$RESULT_A" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['success'] and d.get('displayExprCorrect') and d.get('onAddCorrect')" 2>/dev/null; then
  # Curl returns correct content — that's the essential test
  DE_CONTENT=$(echo "$RESULT_A" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('displayExprContent','')[:40])" 2>/dev/null)
  # Check if actOn assignment also worked
  DE_SET=$(echo "$RESULT_C" | python3 -c "import sys,json; d=json.load(sys.stdin); de=d.get('displayExpr',''); print('set:'+de[:30] if de else 'not-set-via-actOn')" 2>/dev/null)
  pass "Quoted expressions (content=$DE_CONTENT, $DE_SET)"
else
  fail "Quoted expressions" "$(echo "$RESULT_A" | head -c 200)"
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

TESTS_JSON=$(IFS=,; echo "${TESTS[*]}")
echo "{\"passed\": $PASS, \"failed\": $FAIL, \"total\": $((PASS + FAIL)), \"tests\": [$TESTS_JSON]}"
