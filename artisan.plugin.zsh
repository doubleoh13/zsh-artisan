#--------------------------------------------------------------------------
# Laravel artisan plugin for zsh
#--------------------------------------------------------------------------
#
# This plugin adds an `artisan` shell command that will find and execute
# Laravel's artisan command from anywhere within the project. It also
# adds shell completions that work anywhere artisan can be located.

function artisan() {
    local artisan_path=$(_artisan_find)

    if [ "$artisan_path" = "" ]; then
        >&2 echo "zsh-artisan: artisan not found. Are you in a Laravel directory?"
        return 1
    fi

    local artisan_cmd=$(_get_artisan_cmd true)
    [[ -z "$artisan_cmd" ]] && return 1

    local artisan_subcmd=$1
    (( $# > 0 )) && shift

    local artisan_args=()
    local arg
    for arg in $@
    do
        artisan_args+=($(printf "%s" "$arg" | sed "s/'/'\\\\''/g;1s/^/'/;\$s/\$/'/"))
    done

    local artisan_start_time=$(date +%s)

    eval "$artisan_cmd $artisan_subcmd $artisan_args"

    local artisan_exit_status=$? # Store the exit status so we can return it later

    if [[ $1 = "make:"* && $ARTISAN_OPEN_ON_MAKE_EDITOR != "" ]]; then
        # Find and open files created by artisan
        find \
            "$laravel_path/app" \
            "$laravel_path/tests" \
            "$laravel_path/database" \
            -type f \
            -newermt "-$(($(date +%s) - $artisan_start_time + 1)) seconds" \
            -exec $ARTISAN_OPEN_ON_MAKE_EDITOR {} \; 2>/dev/null
    fi

    return $artisan_exit_status
}

compdef _artisan_add_completion artisan

function _get_artisan_cmd() {
    local use_tty=$1

    local artisan_path=$(_artisan_find)
    if [[ -z "$artisan_path" ]]; then
        >&2 echo "zsh-artisan: artisan not found. Are you in a Laravel directory?"
        return 1
    fi

    local laravel_path=$(dirname $artisan_path)
    local env_path="$laravel_path/.env"

    local file_command=
    local file_service=

    if [[ -f "$env_path" ]]; then
        local file_command=$(_get_env_value_from_file $env_path "ARTISAN_COMMAND")
        local file_service=$(_get_env_value_from_file $env_path "ARTISAN_SERVICE")
    fi
    
    local effective_command="${file_command:-${ARTISAN_COMMAND:-}}"
    local effective_service="${file_service:-${ARTISAN_SERVICE:-}}"
    
    if [[ -n "$effective_command" ]]; then
        # If the command is set in the .env file, use it
        echo "$effective_command"
        return 0
    fi
    
    local docker_compose_config_path=$(find $laravel_path -maxdepth 1 \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \) | head -n1)

    if [[ -z "$docker_compose_config_path" ]]; then
        echo "php $artisan_path"
    else
        if [[ "$(grep "laravel/sail" $docker_compose_config_path | head -n1)" != '' ]]; then
            echo "$laravel_path/vendor/bin/sail artisan"
        else
            local docker_compose_cmd=$(_docker_compose_cmd)
            local service="${effective_service:-$($=docker_compose_cmd ps --services 2>/dev/null | grep -E 'app|php|api|workspace|laravel\.test|webhost' | head -n1)}"

            if [[ -z "$service" ]]; then
                >&2 echo "zsh-artisan: unable to determine docker service name"
                return 1
            fi

            if [[ "$use_tty" == true ]]; then
                echo "$docker_compose_cmd exec $service php artisan"
            else
                echo "$docker_compose_cmd exec -T $service php artisan"
            fi
        fi
    fi
}

function _artisan_find() {
    # Look for artisan up the file tree until the root directory
    local dir=.
    until [ $dir -ef / ]; do
        if [ -f "$dir/artisan" ]; then
            echo "$dir/artisan"
            return 0
        fi

        dir+=/..
    done

    return 1
}

function _artisan_add_completion() {
    if [ -n "$(_artisan_find)" ]; then
        compadd $(_artisan_get_command_list)
    fi
}

function _artisan_get_command_list() {
    local artisan_cmd=$(_get_artisan_cmd true)
    [[ -z "$artisan_cmd" ]] && return 1

    eval "$artisan_cmd list --format=json" 2>/dev/null | jq -r '.namespaces[].commands | values[]'
    #artisan --raw --no-ansi list | sed "s/[[:space:]].*//g"
}

function _docker_compose_cmd() {
    docker compose &> /dev/null
    if [ $? = 0 ]; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

function _get_env_value_from_file() {
    local file=$1
    local key=$2

    grep -E "^$key=" "$file" 2>/dev/null | tail -n1 | cut -d '=' -f2- | sed -e 's/^"//' -e 's/"$//'

}
