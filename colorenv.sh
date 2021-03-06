#!/usr/bin/env sh

set -o pipefail

ANSI_ORDER='black red green yellow blue magenta cyan white'
ce_KEYS_etc="name"
ce_KEYS="foreground background $ce_KEYS_etc"

Px=ColorENV
B16_BASE=~/.themes/shell/scripts

ce_ext16() {
    local seq match
    (
      if   [ -r "$1" ]; then match=$1
      elif [ -r "$B16_BASE/base16-$1.sh" ]; then match=$B16_BASE/base16-$1.sh
      elif ! [ -t 0 ]; then match=
      else ce_error 'bad file name; try a base16 theme name, or supply on stdin';
      fi
      eval "$(grep -e ^color $match)"

      for seq in $(seq 0 21); do
          eval echo \$color$(printf %02d $seq)
      done
      echo foreground=$color_foreground
      echo background=$color_background
    )
}

ce_init() {
    ce_setEnv $(ce_ext16 ${1:-default-dark})
}

ce_alternates() { local IFS; IFS='|'; echo "$*"; }
ce_fatal() { ce_error "$@"; exit 1; }
ce_error() { echo '[colorenv error]:' "$@" >&2; return 1; }

ce_loadEnv() {
    local ent key val
    eval set -- \$$Px
    for ent; do
        key=${ent%%=*} val=${ent#*=}
        [ ${#key} -ne ${#ent} ] || { ce_error "bad entry $ent"; continue; }
        eval ${Px}_$key=$val
    done
}

ce_listEnv() {
    set | grep -E "^$Px\_([0-9]+|$(ce_alternates $ce_KEYS))=" \
        | sed "s/^$Px\_//;s/'//g" \
        | sort -g
}
ce_array() { ce_listEnv | sed -n '/^[0-9]/{s/^[^=]*=//;p}'; }

ce_saveEnv() { echo $Px=\'$(ce_listEnv)\'; }

ce_validate_cVal() {
    local work v_lo v_hi2 x
    # caller has to provide a local cVal binding

    cVal=${1###}
    [ ${#cVal} -eq 8 ] && cVal=$(echo "$cVal" | sed 's^/^^g')

    work=$(printf %0${#cVal}x "0x$cVal" 2>/dev/null) || return 1

    cVal=$work
    [ ${#cVal} -eq 6 ] && return 0
    [ ${#cVal} -ne 3 ] && return 1

    v_lo=${cVal#??} v_hi2=${cVal%?}
    cVal=
    for x in ${v_hi2%?} ${v_hi2#?} ${v_lo}; do
        cVal=$cVal$x$x
    done
}

ce_try_pastel() {
    local work
    work=$(pastel format hex "$1") && ce_validate_cVal "$work"
}

_ce_setEnv() {
    local cPair cName cVal envKey idx

    idx=0
    for cPair; do
      case "$cPair" in
        *=*) cVal=${cPair#*=} cName=${cPair%%=*}
             ce_matchKey "$cName" || ce_error "unable to match $cName" ;;
          *) cVal=$cPair; envKey=$idx; idx=$((1 + idx))
             [ $idx -lt 256 ] || ce_error 'only indices 0-255 allowed' ;;
      esac || continue

      # These don't need to be validated as colors
      if ! case " $ce_KEYS_etc " in (*\ $envKey\ *) true;; *) false;; esac &&
              ! ce_validate_cVal "$cVal" &&
              ! ce_try_pastel    "$cVal"  ;
      then { ce_error "invalid color value: $cVal"; continue; } fi

      echo ${Px}_$envKey=$cVal
    done
}

ce_mapFB() {
    local cVal match st
    if ce_validate_cVal "$fg"; then
        match=$(ce_listEnv | grep -s -m1 =$cVal\$) && fg=${match%%=*}
    fi
    st=$?
    if ce_validate_cVal "$bg"; then
        match=$(ce_listEnv | grep -s -m1 =$cVal\$) && bg=${match%%=*}
    fi || return 1
    return $st
}

ce_unmapFB() {
    local cVal st

    eval cVal=\$$Px\_$fg && ce_validate_cVal "$cVal" && fg=$cVal
    st=$?
    eval cVal=\$$Px\_$bg && ce_validate_cVal "$cVal" && bg=$cVal
    return $((st + $?))
}

ce_setEnv() {
    local envStr fg bg cVal COLORS

    COLORS=$(echo "$@"; ce_stdinColors)
    envStr=$(_ce_setEnv $COLORS) || ce_fatal 'problem setting environment. no changes made.'

    case "$ce_autofb" in
      K|M)  eval  fg=\$$Px\_foreground  bg=\$$Px\_background  ;;
    esac
    [ "$ce_autofb" = M ] && ce_mapFB

    eval "$envStr"

    [ "$ce_autofb" ] || return
    case "$ce_autofb" in
      M)  ce_unmapFB ;;
      L)  eval fg=\$$Px\_0 bg=\$$Px\_7 ;;
      D)  eval fg=\$$Px\_7 bg=\$$Px\_0 ;;
    esac

    if ce_validate_cVal "$fg"; then eval $Px\_foreground=$cVal
    else ce_error "[auto fg/bg = $ce_autofb] couldn't validate fg=$fg"; fi

    if ce_validate_cVal "$bg"; then eval $Px\_background=$cVal
    else ce_error "[auto fg/bg = $ce_autofb] couldn't validate bg=$bg"; fi
}

ce_matchKey() {
    local off clr e

    off=0
    echo "$1" | grep -qiE 'bright|bold' && off=8

    clr=$(echo "$1" | grep -sioE "$(ce_alternates $ANSI_ORDER purple)") \
        || clr=$1
    clr=$(echo "$clr" | tr '[:upper:]' '[:lower:]')

    [ "$clr" = purple ] && clr=magenta

    case "$clr" in
      black)  envKey=$off ;;
        red)  envKey=$((1 + off)) ;;
      green)  envKey=$((2 + off)) ;;
     yellow)  envKey=$((3 + off)) ;;
       blue)  envKey=$((4 + off)) ;;
    magenta)  envKey=$((5 + off)) ;;
       cyan)  envKey=$((6 + off)) ;;
      white)  envKey=$((7 + off)) ;;
  [0-9] | [0-9][0-9]) envKey=$clr   ;;
          *)  false ;;
    esac && return

    # misc. whitelist
    eval "case $clr in
        $(ce_alternates $ce_KEYS)) envKey=$clr ;;
        *) return 1 ;;
        esac"
}

ce_rgb_str() {
    local cVal v_lo
    ce_validate_cVal "$1" || return 1
    v_lo=${cVal#??}
    rgb=${cVal%????}/${v_lo%??}/${v_lo#??}
}

_ce_initc() { printf '\e]%s;rgb:%s\e\' "$@"; }

ce_initc() {
    local rgb
    [ "$1" -lt 256 ] || return 1
    ce_rgb_str "$2"     || return 1
    _ce_initc "4;$1" "$rgb"
}

ce_initc_fb() {
    local code rgb
    ce_rgb_str "$1" && _ce_initc 10 "$rgb"
    ce_rgb_str "$2" && _ce_initc 11 "$rgb"
}

ce_escEnv() {
    local seq clr fg bg
  
    for seq in $(seq 0 15); do
        eval ce_initc $seq \$${Px}_$seq
        eval ce_initc $((8 + seq)) \$${Px}_$((8 + seq))
    done
  
    eval fg=\${${Px}_foreground:-\$${Px}_7}
    eval bg=\${${Px}_background:-\$${Px}_0}
    eval ce_initc_fb "$fg" "$bg"
}

ce_colorENV() {
    [ -t 2 ] || ce_fatal 'stderr must be connected to a terminal'
    ce_escEnv >&2
}

ce_stdinColors() {
    [ -t 0 ] && return 0
    set -- $(cat) && echo "$@"
}

t_a_b=$(printf '\e[1m') t_a_u=$(printf '\e[4m') t_a_0=$(printf '\e[0m')

ce_help() { cat >&2; exit 1; } <<EOF
${t_a_u}colorenv.sh${t_a_0}

${t_a_b}USAGE:${t_a_0}
    colorenv.sh  [-l|-a] [-r] [colors ...]

    Colors can be provided on stdin, or following options on the command line.

${t_a_b}OPTIONS${t_a_0}:
 ${t_a_b}-l${t_a_0}  list
 ${t_a_b}-a${t_a_0}  apply
 ${t_a_b}-r${t_a_0}  reset
EOF

ce_explodeOpt() { echo -n "$1" | (while read -r -n1 char; do echo -$char; done); }

ce_parseOpts() {
    local orig opt;  orig=$#

    while [ $# -gt 0 ] && [ -z "${1%%-*}" ]; do
        opt=${1#-}; shift
        case "$opt" in
    ?[a-zA-Z]*) set -- $(ce_explodeOpt "$opt") "$@" ;;
             l) ce_list=1  ;;
             a) ce_apply=1 ;;
             r) ce_reset=1 ;;
       L|D|K|M) ce_autofb=$opt ;;
          h|\?) ce_help    ;;
             *) return 1 ;;
        esac
    done
    ce_SHIFTS=$((orig - $#))
}
if [ $(basename "$0") = colorenv.sh ]; then
    ce_parseOpts "$@"; shift $ce_SHIFTS

    [ "$ce_reset" ] ||  ce_loadEnv

    ce_setEnv "$@"

    [ "$ce_apply" ] &&  ce_colorENV
    [ "$ce_list"  ] &&  ce_listEnv &&  exit # keep stdout coherent
    ce_saveEnv
fi
