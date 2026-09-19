# bash completion for atf
_atf()
{
    local cur prev i
    COMPREPLY=()
    cur=${COMP_WORDS[COMP_CWORD]}
    prev=${COMP_WORDS[COMP_CWORD-1]}

    case "$prev" in
        -e|--every)
            COMPREPLY=( $(compgen -W "30s 1m 5m 15m 30m 1h 2h 6h 12h 1d" -- "$cur") )
            return
            ;;
    esac

    # After "--", complete the command.
    for ((i = 1; i < COMP_CWORD; i++)); do
        if [[ ${COMP_WORDS[i]} == -- ]]; then
            COMPREPLY=( $(compgen -A command -- "$cur") )
            return
        fi
    done

    if [[ $cur == -* ]]; then
        COMPREPLY=( $(compgen -W "-q --quiet -p --print -f --force -P --pretty --progress -e --every -h --help -v --version" -- "$cur") )
        return
    fi

    COMPREPLY=( $(compgen -W "now noon midnight tomorrow today :00 :15 :30 :45 1m 5m 1h" -- "$cur") )
}

complete -F _atf atf
