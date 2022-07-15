#!/bin/bash
PS4='Line ${LINENO}: '

PROGRAM_NAME="$0"

ARGS=`getopt -o hd: --long debug,help,exclude::,bk-dir: -n "$0" -- "$@"`
if [ $? != 0 ]; then
  echo "Terminating..."
  exit 1
fi

eval set -- "${ARGS}"
echo formatted parameters=[$@]

EXCLUDE_RE='$^'
DEBUG=false
while true
do
  case "$1" in
    -h|--help)
      echo "${PROGRAM_NAME} [-h|--help] (--bk-dir|-d)=BACKUP_DESTINATION [--exclude=REGEX_PATTERN] dir1 [dir2...]"
      shift
      exit 0
    ;;
    --exclude)
      EXCLUDE_RE=$2
      shift 2
    ;;
    --bk-dir|-d)
      BACKUP_DESTINATION=$2
      if [[ $BACKUP_DESTINATION == .* ]]; then
        BACKUP_DESTINATION=("${PWD}${BACKUP_DESTINATION:1}")
      elif [[ $BACKUP_DESTINATION == ~* ]]; then
        BACKUP_DESTINATION=("${HOME}${BACKUP_DESTINATION:1}")
      elif [[ $BACKUP_DESTINATION != /* ]]; then
        BACKUP_DESTINATION=("${PWD}/${BACKUP_DESTINATION}")
      fi
      shift 2
    ;;
    --debug)
      DEBUG=true
      shift
    ;;
    --)
      shift
      for d in $@; 
      do
        ls -d ${d} 2> /dev/null > /dev/null || continue
        # relative or absolute path
        if [[ $d == .* ]]; then
          DIRS+=("${PWD}${d:1}")
        elif [[ $d == ~/* ]]; then
          DIRS+=("${HOME}{d:1}")
        elif [[ $d != /* ]]; then
          DIRS+=("${PWD}/${d}")
        else
          DIRS+=("${d}")
        fi
        DIRS[-1]=$(echo "${DIRS[-1]}/" | sed 's/\/\{1,2\}$/\//g') #guarantee one slash in the end of d
      done
      if [ ${#DIRS} -eq 0 ]; then
        echo 'No specify any directory, terminate'
        exit 1
      fi
      break
    ;;
    *)
      echo "invalid input, terminate"
      echo "type: ${PROGRAM_NAME} (-h|--help) for help"
      exit 1
    ;;
  esac
done
echo exclude_re:$EXCLUDE_RE BACKUP_DESTINATION:$BACKUP_DESTINATION DIRS: ${DIRS[@]}

if $DEBUG; then
  set -x
fi

# init backup_destination
function init_dir() {
  echo "initializing..."
  # mkdir if desination is not found.
  ls -d $BACKUP_DESTINATION 2&>1 > /dev/null || (mkdir -p $BACKUP_DESTINATION; touch "${BACKUP_DESTINATION}/backuping.txt")
  for d in ${DIRS[@]}; do
    dst_name=$(echo ${d} | tr '/' '_')
    dst_root="${BACKUP_DESTINATION}/${dst_name}"
    
    # init directory in destination.
    ls -d "${dst_root}" 2&>1 > /dev/null && continue
    echo "initializing ${dst_root}"
    echo "${d} ${dst_root}" >> "${BACKUP_DESTINATION}/backuping.txt"
    mkdir -p "${dst_root}"
    touch "${dst_root}/change_log.txt"
    cp -r ${d} "${dst_root}/latest/"
    cd "${dst_root}/latest/" && git init > /dev/null && git add * && git commit -m 'initial commit' > /dev/null
    echo "${dst_root} initialized"
  done
  echo "init done"
}

function update_backup() {
  changed_file="${1}${3}"
  events="$2"
  echo "detect file change: ${events} ${change_file}"
  cur_time=$(printf '%(%F:%T)T.%06.0f\n' ${EPOCHREALTIME/./ })
  for d in ${DIRS[@]}; do
    if [[ $changed_file == $d* ]]; then
      #d=$(echo "${d}/" | sed 's/\/\{1,2\}$/\//g') #guarantee one slash in the end of d
      dst_name=$(echo ${d} | tr '/' '_')
      dst_root="${BACKUP_DESTINATION}/${dst_name}"
      echo "${cur_time} ${events} ${changed_file}" >> "${dst_root}/change_log.txt"
      relative_path=${changed_file:${#d}}
      sync_dst="${dst_root}/latest/${relative_path}"
      echo "updating ${dst_root}, ${relative_path}, ${sync_dst}"
      if [[ $events == *ISDIR* ]]; then
        if [[ $events == *DELETE* ]]; then
          rmdir "${sync_dst}"
        else
          cp -r ${changed_file} "${sync_dst}"
        fi
      else
        if [[ $events == *DELETE* ]]; then
          rm "${sync_dst}"
        else
          cp ${changed_file} "${sync_dst}"
        fi
      fi
      cd "${dst_root}/latest" && git add "${sync_dst}" && git commit -m "${events} ${change_file}:${sync_dst}"
    fi
  done
}

function main() {
  init_dir
  dirs_str=""
  for d in ${DIRS[@]}; do
    dirs_str="${dirs_str} ${d}"
  done
  cd /
  inotifywait -qmr -e CREATE -e MODIFY -e DELETE --exclude ${EXCLUDE_RE} ${dirs_str} | \
    while read -r a b c; do
      update_backup $a $b $c
    done
}
main

if $DEBUG; then
  set +x
fi
