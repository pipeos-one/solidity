#!/usr/bin/env bash

set -e

ROOT_DIR=$(readlink -f "$(dirname "$0")"/..)
WORKDIR="${ROOT_DIR}/build/antlr"
ANTLR_JAR="${ROOT_DIR}/build/deps/antlr4.jar"
ANTLR_JAR_URI="https://www.antlr.org/download/antlr-4.8-complete.jar"

SGR_RESET="\033[0m"
SGR_BOLD="\033[1m"
SGR_GREEN="\033[32m"
SGR_RED="\033[31m"
SGR_BLUE="\033[34m"

vt_cursor_up() { echo -ne "\033[A"; }
vt_cursor_begin_of_line() { echo -ne "\r"; }

download_antlr4()
{
  if [[ ! -e "$ANTLR_JAR" ]]
  then
    curl -o "${ANTLR_JAR}" "${ANTLR_JAR_URI}"
  fi
}

prepare_workdir()
{
  mkdir -p "${ROOT_DIR}/build/deps"
  mkdir -p "${WORKDIR}"
  mkdir -p "${WORKDIR}/src"
  mkdir -p "${WORKDIR}/target"
}

prepare_workdir
download_antlr4

if [[ ! -f "${WORKDIR}/target/SolidityParser.class" ]] || \
    [ "${GRAMMAR_FILE}" -nt "${WORKDIR}/target/SolidityParser.class" ]
then
  echo "Creating parser"
  (
  cd "${ROOT_DIR}"/docs/grammar
  # Create lexer/parser from grammar
  java -jar "${ANTLR_JAR}" Solidity.g4 SolidityLexer.g4 -o "${WORKDIR}/src/"

  # Compile lexer/parser sources
  javac -classpath "${ANTLR_JAR}" "${WORKDIR}/src/"*.java -d "${WORKDIR}/target/"
  )
fi

# Run tests
failed_count=0
test_file()
{
  local SOL_FILE
  SOL_FILE="$(readlink -m "${1}")"
  local cur=${2}
  local max=${3}

  echo -e "${SGR_BLUE}[${cur}/${max}] Testing ${SOL_FILE}${SGR_RESET} ..."
  local output
  output=$(
    java \
      -classpath "${ANTLR_JAR}:${WORKDIR}/target/" \
      "org.antlr.v4.gui.TestRig" \
      Solidity \
      sourceUnit <"${SOL_FILE}" 2>&1
  )
  vt_cursor_up
  vt_cursor_begin_of_line
  if grep -qE "^\/\/ ParserError" "${SOL_FILE}"; then
    if [[ "${output}" != "" ]]
    then
      echo -e "${SGR_BLUE}[${cur}/${max}] Testing ${SOL_FILE}${SGR_RESET} ${SGR_BOLD}${SGR_GREEN}FAILED AS EXPECTED${SGR_RESET}"
    else
      echo -e "${SGR_BLUE}[${cur}/${max}] Testing ${SOL_FILE}${SGR_RESET} ${SGR_BOLD}${SGR_RED}SUCCEEDED DESPITE PARSER ERROR${SGR_RESET}"
      echo "${output}"
      failed_count=$((failed_count + 1))
      exit 1
    fi
  else
    if [[ "${output}" == "" ]]
    then
      echo -e "${SGR_BLUE}[${cur}/${max}] Testing ${SOL_FILE}${SGR_RESET} ${SGR_BOLD}${SGR_GREEN}OK${SGR_RESET}"
    else
      echo -e "${SGR_BLUE}[${cur}/${max}] Testing ${SOL_FILE}${SGR_RESET} ${SGR_BOLD}${SGR_RED}FAILED${SGR_RESET}"
      echo "${output}"
      failed_count=$((failed_count + 1))
      exit 1
    fi
  fi
}

# we only want to use files that do not contain excluded parser errors, analysis errors or multi-source files.
SOL_FILES=()
while IFS='' read -r line
do
  SOL_FILES+=("$line")
done < <(
  grep -riL -E \
    "^\/\/ (Syntax|Type|Declaration)Error|^\/\/ ParserError (6275|3716|6281|2837|6933)|^==== Source:" \
    "${ROOT_DIR}/test/libsolidity/syntaxTests" \
    "${ROOT_DIR}/test/libsolidity/semanticTests" \
)

test_count=0
for SOL_FILE in "${SOL_FILES[@]}"
do
  test_count=$((test_count + 1))
  test_file "${SOL_FILE}" ${test_count} ${#SOL_FILES[*]}
done

echo "Summary: ${failed_count} of ${#SOL_FILES[*]} sources failed."
exit ${failed_count}
