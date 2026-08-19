function normalize_pc(value, pc) {
    pc = tolower(value)
    sub(/:$/, "", pc)
    sub(/^0+/, "", pc)
    return (pc == "") ? "0" : pc
}

# Read symbols and disassembled instructions from main.dump first.
NR == FNR {
    if ($0 ~ /^Disassembly of section /) {
        in_text = ($0 == "Disassembly of section .text:")
        next
    }

    if (!in_text) {
        next
    }

    if ($1 ~ /^[[:xdigit:]]+$/ && $2 ~ /^<[^>]+>:$/) {
        symbol[normalize_pc($1)] = $2
        next
    }

    if ($1 ~ /^[[:xdigit:]]+:$/ && $2 ~ /^[[:xdigit:]]+$/) {
        pc = normalize_pc($1)
        text = $0
        sub(/^[[:space:]]*[[:xdigit:]]+:[[:space:]]+[[:xdigit:]]+[[:space:]]+/, "", text)
        assembly[pc] = text
    }
    next
}

$1 == "#" {
    print "# retire pc       insn      assembly"
    next
}

{
    pc = normalize_pc($2)
    if (pc in symbol) {
        print ""
        print symbol[pc]
    }

    if (pc in assembly) {
        printf "%s %s %s  %s\n", $1, $2, $3, assembly[pc]
    } else {
        printf "%s %s %s  <unknown>\n", $1, $2, $3
    }
}
