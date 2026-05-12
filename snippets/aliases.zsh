alias -g la='eza -a'

alias mv='mv -iv'
alias cp='cp -riv'
alias md='mkdir -vp'
alias diff='diff --color=auto'
alias md5='md5sum'
alias wcl='wc -l'
alias wcc='wc -c'
alias f='fd -HI'
alias le='less'
alias lesss='less'
alias x='xargs '
alias F='fzf'
alias rp='realpath'
alias rp.='realpath .'
alias rp.c='realpath . | c'
alias pwdc='pwd | tr -d "\n" | c'
alias S='du -sh'
alias filesize='du -h'
alias biggest-files='du -hsx * | sort -rh | head -10'
alias ducks='ls -a | xargs du -cks -- | sort -rn'
alias dush.='du -sh .'
alias dfh='df -h'
alias wdf='watch df '
alias wdfh='watch df -h '
alias wduh='watch du -sh '
alias wdu='watch -n1 du -s "*" '
alias wdush.='watch du -sh . '
alias rmempty='find . -type d -empty -delete'
alias empty-trash='command rm -rf ~/.local/share/Trash/*'
alias lst='ls -t'
alias lwcl='ls | wc -l'
alias wl='watch ls '
alias wll='watch ls -lh '
alias wla='watch la '
alias wls='watch ls '
alias wt='watch -n1 tree '
alias wtree='watch tree '
alias wtail='watch tail '
alias ws='watch stat '
alias wstat='watch stat '
alias wmd5='watch md5sum '
alias wmd5.='watch md5sum * '
alias wag='watch ag '
alias wgs='watch git status '
alias fsw='fswatch .'

alias v='nvim'
alias sv='sudoedit'
alias se='sudo -E '
alias v-='v -'
alias vc='co | v -'
alias vh='nvim ~/.local/state/zsh/history'
alias lh='less ~/.local/state/zsh/history'
alias vig='v .gitignore'
alias vre='v README.md'
alias vm='[[ -f CMakeLists.txt ]] && v CMakeLists.txt || v Makefile'
alias vcm='v CMakeLists.txt'
alias V='nvim -c "let g:startify_disable_at_vimenter=1"'
alias vi='V'
alias vt='v .travis.yml'
for _i in {0..9}; do alias "v$_i"="nvim -c \"normal ''$_i\""; done; unset _i
alias nvimdiff='nvim -d'
alias vimdiff='nvim -d'
vx() { xxd "$@" | v - }

alias cfv='v /etc/nixos/mandragora/.config/nvim/init.lua'
alias cfz='v /etc/nixos/mandragora/.config/zsh/zshrc.zsh'
alias cfh='v /etc/nixos/mandragora/.config/hypr/hyprland.conf'
alias cft='v /etc/nixos/mandragora/.config/tmux/tmux.conf'
alias cfw='v /etc/nixos/mandragora/modules/user/waybar.nix'
alias cfm='v /etc/nixos/mandragora/modules/user/home.nix'
alias cfl='v /etc/nixos/mandragora/modules/user/lf.nix'
alias cfN='v /etc/nixos/mandragora/.config/ncmpcpp/'
alias cfmu='v /etc/nixos/mandragora/.config/ncmpcpp/'
alias cfK='v /etc/nixos/mandragora/.config/keyledsd/keyledsd.conf'
alias cfZ='v /etc/nixos/mandragora/.config/zathura/zathurarc'
alias cfM='v /etc/nixos/mandragora/.config/mpv/mpv.conf'
alias cfC='v /etc/nixos/mandragora/.config/nvim/lua/config/'
alias cfR='v /etc/nixos/mandragora/.config/rofi/'
alias cfpy='v /etc/nixos/mandragora/.config/ptpython/config.py'
alias cfpa='v /etc/nixos/mandragora/modules/user/zsh.nix'
alias cfD='sh -c "cd /etc/nixos/mandragora && git diff"'

# "cf"-tabbing descriptions
_cf_aliases() {
    local -a configs
    configs=(
        'cfv:Neovim init.lua'
        'cfz:Zsh shell config (zshrc.zsh)'
        'cfh:Hyprland main config'
        'cft:Tmux config'
        'cfw:Waybar Nix module'
        'cfm:Home Manager main module'
        'cfl:lf file manager config dir'
        'cfN:ncmpcpp config dir'
        'cfmu:ncmpcpp config dir (alias)'
        'cfK:keyledsd config'
        'cfZ:zathura PDF viewer config'
        'cfM:mpv player config'
        'cfC:Neovim lua/config/ dir'
        'cfR:rofi menu config dir'
        'cfpy:ptpython config'
        'cfpa:Zsh Nix module'
        'cfD:NixOS repo git diff'
    )
    _describe -t configs 'config aliases' configs
}
compdef _cf_aliases -P 'cf*'

d() { trash "$@" }
ud() { trash-restore }
alias rmr='command rm -r'

cow() { co | xargs wget }
alias cocat='cat "$(co)"'
alias cozat='zathura "$(co)"'
alias cosv='sudoedit "$(co)"'
alias corm='command rm "$(co)"'
alias cormr='co | xargs command rm -r'
alias cocp='cp "$(co)"'
cocp.() { cp "$(co)" . }
comv.() { mv "$(co)" . }
alias cowv='co | xargs wget'
alias corpc='co | xargs -I{} realpath "{}" | c'
alias cofile='co | xargs file'
alias cojq='co | jq'
alias cojqv-='co | jq | v -'
alias cocurl='co | xargs curl -s'
alias cocurll='co | xargs curl -s | less'
alias cocd='eval "$(co)"'
cocp.() { cp "$(co)" . }
co2ip() { f=/tmp/co2i-$(date +%s).png; wl-paste --type image/png > "$f" && echo -n "$f" }
co2ipc() { co2ip | c }
co2nsxiv() { wl-paste --type image/png > /tmp/img; nsxiv /tmp/img }
alias cov='nvim "$(co)"'

alias p='P | tr -d "\n" | c'

alias weather='curl -s wttr.in | head -n -1'
alias W='curl -s v2.wttr.in | head -n -1'
alias serve='python3 -m http.server 2717'
alias getredir='curl -Ls -o /dev/null -w %{url_effective}'
alias cu='curl'
alias timecurl='curl -w "%{time_total}"'
alias ns='notify-send'
alias scanlan='nmap -p80,443 192.168.0.0/24 -oG -'
alias scanvuln='nikto -h -'
alias gibberish='tr -cd "[:alnum:]" < /dev/urandom | head; echo'
alias randip="dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tu1 | sed -e 's/^ *//;s/  */./g'"
knock() { nc -z -w3 "$1" "$2"; echo $? }
shortenurl() { curl "https://is.gd/create.php?format=simple&url=$1" }
servesingle() {
  [[ -z $1 ]] && return 1
  fp=$(realpath "$1")
  { echo -ne "HTTP/1.0 200 OK\r\nAccess-Control-Allow-Origin: *\r\nContent-Disposition: filename=\"$(basename "$fp")\"\nContent-Length: $(wc -c < "$fp")\r\n\r\n"; cat "$fp"; } | nc -l -p 2717
}
alias sS='servesingle'
linktcp() { socat "tcp-l:$1,fork,reuseaddr" "tcp:127.0.0.1:$2" }

alias pull='git pull'
alias gP='git pull'
alias ga.='git add .'
alias gdd='git diff HEAD~1'
alias gddd='git diff HEAD~2'
alias gdddd='git diff HEAD~3'
alias gddddd='git diff HEAD~4'
alias gddv-='git diff HEAD~1 | v -'
alias gsu='git ls-files . --exclude-standard --others'
alias gsi='git ls-files . --ignored --exclude-standard --others'
alias gsc='git stash clear'
alias gsa='git stash apply'
alias gsp='git stash pop'
alias gssp='git stash show -p'
alias gmm='git merge master'
alias gri='git rebase -i'
alias gcob='git checkout -b'
alias gcom='git checkout master'
alias gpsu='git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)'
alias grao='git remote add origin'
alias GD='git daemon --base-path=. --export-all'
alias gaca='git add .; git commit --amend'
alias lg='lazygit'
alias coga='co | git apply'
gcm() { git commit -m "$*" }
gca() { local msg="$*"; git add .; [[ -z $msg ]] && git commit -a || git commit -m "$msg" }
gcap() { gca "$@" && git push }
gacap() { gaca; git push -f "$@" }
gbd() { git branch -d "$@" && git push origin --delete "$@" }
gg() { git grep "$@" $(git rev-list --all) }
gC() { git config pack.threads 1; git config pack.deltaCacheSize 1; git config core.packedGitWindowSize 16m; git config core.packedGitLimit 128m; git config pack.windowMemory 512m; git gc --aggressive; git prune }
git-obliterate() { git filter-branch -f --index-filter "git rm -rf --cached --ignore-unmatch $@" HEAD }
gdc() { git diff HEAD HEAD~1 }
gcd() { [[ $# -eq 1 ]] && git diff "$1" }
gd() { [[ "$#" -eq 1 ]] && git diff "$@" || { git ls-files -o --exclude-standard | xargs -I{} git add {} 2>/dev/null; git add .; git diff --staged; git reset 2>/dev/null } }

alias D='date "+%d-%m-%Y %H:%M"'
alias whatisthis='uname -mrs'
alias H='cd -'
alias poof='shutdown -h 0'
alias ctl='systemctl'
alias sctl='sudo systemctl'
alias smv='sudo mv'
alias srm='sudo rm'
alias schmod='sudo chmod'
alias schown='sudo chown'
alias slns='sudo ln -s'
alias sf='sudo find / -iname'
alias fuck='sudo '
alias ka='killall -I'
alias pk='pkill'
alias scan4sd='echo 1 | sudo tee /sys/bus/pci/rescan'
alias top='btop'

wpa() { watch "ps aux | grep \"$@\" | head -n -1" }

alias g='grep -i'
alias gv='grep -v'
alias a='ag'
alias ag='ag --search-binary --hidden --color'
alias jsonify='jq .'
alias uppercase="sed 's/[^ ]\+/\U&/g'"
alias lowercase="sed 's/[^ ]\+/\L&/g'"
alias capitalize="sed 's/[^ ]\+/\L\u&/g'"
alias first='sed 1q'
alias t1='tail -n1'
alias unquote="sed 's/^\"//g;s/\"$//g'"
alias trdn='tr -d "\n"'
alias base64='base64 -w0'
alias e='echo'
alias en='echo -n'
append() { [[ "$#" -eq 2 ]] && grep -FIxvf "$2" "$1" | head -n -1 >> "$2" }
urldecode() { echo "$@" | awk -niord '{printf RT?$0chr("0x"substr(RT,2)):$0}' RS=%.. }
urlencode() { python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))" }
replaceall() { find . -type f -iname "$1" -print0 | xargs -0 sed -i "s|$2|$3|g" }
when() { ag --nocolor "$@" ~/.local/state/zsh/history | cut -d' ' -f2- | cut -d: -f1 | xargs -I{} date -d@{} }

cdf() { cd "$(fd -HI "*$@*" | head -n1)" }
fv() { fd -HI -tf "*$@*" | head -n1 | xargs nvim }
vf() { find . -type f -name "*$@*" -exec nvim {} + }
vg() { grep -ril "*$@*" | head -n1 | xargs nvim }
vw() { nvim "$(which "$1")" }
svw() { sudoedit "$(which "$1")" }
cdt() { cd "$(dirname "$(readlink -f "$(which "$1")")")" }
wf() { watch fd -HI "$@" }
wlwcl() { watch 'ls | wc -l' }
mdcd() { mkdir -p "$@"; cd "$_" }
cdd() { local p="$(dirname "$@")"; cd "${p/#\~/$HOME}" }
cocdd() { cdd "$(co)" }
hrmr() { local d="$(basename "$(pwd)")"; cd ..; command rm -r "$d" }
xdiff() { [[ "$#" -eq 2 ]] && nvim -d <(xxd "$1") <(xxd "$2") }
alb() { ln -s "$(realpath "$1")" "$HOME/.local/bin/$(basename -- "$1")" }
_at() { nohup "$@" 2>&1 >/dev/null & disown }
alias @="_at "
o() { nohup xdg-open "$@" 2>&1 >/dev/null & }
O() { nohup xdg-open "$@" 2>&1 >/dev/null &; exit }
tf() { tail -f "$1" 2>&1 | perl -ne 'if (/file truncated/) {system("clear"); print} else {print}' }
t2d() { date -d "@$(cat -)" }
_keep() { while :; do "$@"; done }
alias keep="_keep "
_wtd() { while true; do "$@"; done }
alias wtd="_wtd "
_domany() { local n=99999; [[ "$1" == "-n" ]] && { n=$2; shift 2; }; for i in {1..$n}; do sh -c "$*"; done }
alias domany="_domany "
_onf() { inotifywait -m . -e create -e moved_to | while read pathe action filet; do echo "$filet" | xargs -I{} "$@"; done }
alias onf="_onf "
aka() { grep "$@" /etc/hosts | cut -d' ' -f1 }
throw() { local fp=$(realpath "$1" | cut -c9-); (cd "$HOME"; rsync -R "$fp" "$2":~) }
sshasap() { while ! nc -z -w1 "$1" 22; do sleep 1; done; ssh "$1" }

alias u='unp -U'
alias unp='unp -U'
Zt() { tar -czvf "$1.tar.gz" "${@:2}" }
Zz() { [[ "$#" -ge 2 ]] && zip -r "$1.zip" "${@:2}" }
ti() { tar -czf - "$@" > ~/.tarchive.tar }
to() { tar -xzv < ~/.tarchive.tar }

webm2mp4() { ffmpeg -i "$1" -vf "pad=ceil(iw/2)*2:ceil(ih/2)*2" -crf 26 "${1%.*}.mp4" }
webm2mp3() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.mp3" }
webm2gif() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.gif" }
gif2mp4() { ffmpeg -i "$1" -crf 26 "${1%.*}.mp4" }
mp42gif() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.gif" }
mp42mp3() { [[ $# -eq 1 ]] && ffmpeg -i "$1" -vn -acodec libmp3lame -ab 192k "${1%%.*}.mp3" }
mp42webm() { ffmpeg -i "$1" -crf 26 "${1%.*}.webm" }
mp42avi() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.avi" }
mp4-minus-sound() { ffmpeg -y -i "$1" -an -c:v copy "${1%.mp4}-nosound.mp4" }
avi2mp4() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.mp4" }
mkv2mp4() { ffmpeg -i "$1" -crf 26 "${1%.*}.mp4" }
mkv2webm() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.webm" }
mkv2gif() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.gif" }
ogg2mp3() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.mp3" }
ogg2mp4() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.mp4" }
ogg2wav() { [[ $# -eq 1 ]] && ffmpeg -i "$1" "${1%%.*}.wav" }
webp2png() { dwebp "$1" -o "${1%%.*}.png" && command rm "$1" }
avif2png() { avifdec "$1" "${1%%.*}.png" && trash "$1" }
pdf2png() { [[ $# -eq 1 ]] && pdftoppm "$1" /tmp/slicedPDF -png && convert /tmp/slicedPDF* -gravity center -append "${1%%.*}.png" && command rm /tmp/slicedPDF* }
pdf2jpg() { [[ $# -eq 1 ]] && pdftoppm "$1" /tmp/slicedPDF -jpg && convert /tmp/slicedPDF* -gravity center -append "${1%%.*}.jpg" && command rm /tmp/slicedPDF* }
epub2pdf() { pandoc --pdf-engine=xelatex -f epub -t pdf "$1" -o "${1%%.*}.pdf" }
v2whatsapp() { ffmpeg -i "$1" -c:v libx264 -profile:v baseline -level 3.0 -pix_fmt yuv420p "${1%.*}-whatsapp.${1##*.}" }
gource2mp4() { gource -s .06 -1280x720 --auto-skip-seconds .1 --multi-sampling --stop-at-end --key --highlight-users --hide mouse,progress,filenames,dirnames --file-idle-time 0 --max-files 0 --font-size 22 --title "$(basename "$(realpath .)")" --output-ppm-stream - --output-framerate 30 | ffmpeg -i - -b:v 3048780 -vcodec libx264 -crf 24 gource.mp4 }
ytdl() { yt-dlp -4 -w --extract-audio --audio-format "mp3" -o "$HOME/Music/%(title)s.%(ext)s" "$@" }
coytdl() { yt-dlp "$(co)" }
coy() { ytdl "$(co)" }
ytpl() { mpv --script-opts=ytdl_hook-try_ytdl_first=yes "ytdl://ytsearch:$*" }
alias yts='ytpl'

alias nsxiv='nsxiv'
alias i='nsxiv -ft *'
alias I='nsxiv'
alias sxiv='nsxiv'
alias cosnsxiv='nsxiv "$(co)"'

alias msk='ncmpcpp'
alias mviz='ncmpcpp --screen visualizer'

countdown() { local d=$(( $(date +%s) + $1 )); while [[ $d -ge $(date +%s) ]]; do echo -ne "$(date -u --date @$(( d - $(date +%s) )) +%H:%M:%S)\r"; sleep 0.1; done }
stopwatch() { local d=$(date +%s); while true; do echo -ne "$(date -u --date @$(( $(date +%s) - d )) +%H:%M:%S)\r"; sleep 0.1; done }
timer() { countdown "$1" && for i in {1..3}; do beep -l 300; sleep 0.5; done }
alias sanduba='timer $((6*60)) && notify-send sanduba'
alias lasagna='timer $((11*60)) && for i in {1..4}; do beep -l 400; sleep 0.6; done'

alias enc='openssl aes-256-cbc -in'
dec() { openssl aes-256-cbc -in "$@" -d 2>/dev/null }
x2c() { printf "\\$(printf '%03o' "$1")" }
bin2dec() { echo "$(( 2#$(cat -) ))" }
alias dec2hex='printf "%x\n"'
hex2dec() { echo "${@}" | tr '[:lower:]' '[:upper:]' | xargs echo "obase=10; ibase=16;" | bc }
gcd() { (( $1 % $2 )) && gcd $2 $(( $1 % $2 )) || echo $2 }
die() { echo $(( RANDOM % $1 )) }
alias coinflip='die 2'
isprime() {
  [[ $1 -le 1 ]] && return 1
  [[ $1 -le 3 ]] && return 0
  (( $1 % 2 == 0 || $1 % 3 == 0 )) && return 1
  local i=5
  while (( i * i <= $1 )); do
    (( $1 % i == 0 || $1 % (i+2) == 0 )) && return 1
    (( i += 6 ))
  done
  return 0
}

alias rh='runhaskell'
alias jj='java -jar'
alias swipl='swipl -q'
alias prolog='swipl'
alias pytest='pytest -s'
alias pie.='pip install -e .'
alias piur='pip install --user -r requirements.txt'
alias piu='pip install --user --upgrade --break-system-packages'
alias pir='pip uninstall --no-cache-dir --break-system-packages'
alias piup='pip install --upgrade pip'
alias nig='npm i -g'
C() { make "${1%.*}"; ./"${1%.*}" }
funccount() { nm "$@" | grep "T " | grep -v " _" | wc -l }
mentr() { ls | entr -c make }
nentr() { ls *.* | entr -c node /_ "$@" }
jentr() { ls *.java | entr -c javac '*' }
ptentr() { fd "\\.py" | entr -c pytest --cov-report term-missing --cov="$(basename "$(pwd)")" -s test*/*.py }

alias ds='docker stats'
alias drmi='docker rmi'
alias dcub='docker-compose up --build'
alias dcu='docker-compose up'
alias dcud='docker-compose up -d'
alias dcd='docker-compose down'
dbt() { docker build -t "$@" . }

alias rh='runhaskell'
alias tron='ssh sshtron.zachlatta.com'
alias sdf='ssh mvrozanti@sdf.org'
alias ecdsa='ssh-keygen -l -f /etc/ssh/ssh_host_ecdsa_key.pub'
alias tnsd='tmux new-session -d -s "" sh -c'
alias sum='python3 -c "import sys; print(sum(float(l) for l in sys.stdin))"'
alias myMACs="ip a | grep -EB1 '([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})'"
alias tfl='tail -f *.log'
alias leet='toilet -f rusto'
alias figlet='figlet -t'
alias clock='peaclock'
alias zat='zathura'
alias sc='sc-im'
lo() { libreoffice "$1" 2>&1 >/dev/null & }
alias jn='jupyter notebook'
alias showcolors='for a in {40..47}; do echo -ne "\e[0;30;${a}m  \e[0;37;39m "; done'
alias diff='diff --color=auto'
alias make-gource-mandragora='git --no-pager log --date=raw | grep -E "^\s+.+|Date" | sed -E "s/Date:\s+//g" | sed "N;s/\n//" | sed -E "s/(\S+)\s-\S+\s+(.+)/\1|\2/g" > caption_file'
alias tls='task list'
td() { [[ -n "$@" ]] && task "$@" delete }
alias ta='task add'
rpc() { realpath "$@" | c }

sa() { awk -v name="$*" 'BEGIN{re="^(alias )?"name"(=|\\()"} $0~re{p=1;print;if($0~"^alias "||$0~"}.*;? *$")p=0;next} p{print;if($0~"^} *;? *$")p=0}' "${BASH_SOURCE[0]:-${(%):-%x}}" }

alias claude='claude'
alias gemini='gemini -y'
alias qwen='qwen -y'

alias hhh='cd ../../..'
alias hhhh='cd ../../../..'
alias hhhhh='cd ../../../../..'
alias 2h='hh'
alias 3h='hhh'
alias 4h='hhhh'

alias wh='watch head '
alias wjq='watch jq '
wlg() { watch "ls | grep $@" }
wtg() { watch "tree | grep $@" }

alias wav2ogg='oggenc -q 3 -o file.ogg'
mp32wav() { mpg123 -w "${1%.*}.wav" "$1" }

alias gai='git add -i'
alias gcfd='git clean -f -d'
gbm() { [[ "$#" -eq 2 ]] && git branch -m "$1" "$2" }

v.()      { nvim . }
_ec()      { eval "$*"; echo $? }
alias ec="_ec "
www()     { ww -w $COLUMNS }
getpass() { python3 -c 'from getpass import getpass; print(getpass("Password: "))' }

alias G='googler -l en -n 6'
coG()     { G "$(co)" }

cof()      { f "$(co)" }
coag()     { ag "$(co)" }
costat()   { stat "$(co)" }
cowcc()    { co | wc -c }
alias cox='co | xargs '
cosrm()    { sudo rm "$(co)" }
scov()     { sudoedit "$(co)" }
covipec()  { co | vipe | c }
cogc()     { [[ -d .git ]] && git submodule add "$(co)" || git clone "$(co)"; cd "$(basename "$(co)" .git)" }
cogacp()   { gaca; git push -f "$@" }
alias cotra='transmission-remote -a "$(co)"'
alias trc='tremc'
alias trm='rustmission'

alias sducks='sudo ls -a | xargs du -cks -- | sort -rn'
lnb()     { ln -s "$(realpath "$1")" "$HOME/.local/bin/${2:-$(basename "$1" | cut -d. -f1)}" }
mvcd()    { mv "$@"; cd "${@: -1}" }
ter2dec() { echo "$((3#$(cat -)))" }
xlx()     { f -tnew | xargs file | grep ELF | sed 1q | cut -d':' -f1 | xargs -I{} zsh -c ./{} }
vX()      { echo | vipe | xargs -0 zsh -c }

k9() {
  if [[ $# -eq 0 ]]; then K9
  elif [[ "$1" =~ ^[0-9]+$ ]]; then kill -9 "$1"
  else pkill -9 -i -f "$@"
  fi
}
