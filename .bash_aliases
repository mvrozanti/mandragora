alias rm='rm -f'
# alias ll='ls -alFh'
# alias la='ls -la'
# alias l='ls --sort=time'
alias l=exa
alias watch='watch --color -n2'
alias grep='egrep --color'
alias sp='sudo pacman'
alias sps='sudo pacman -S'
alias spr='sudo pacman -R'
alias pss='pacman -Ss'
alias spsyu='sudo pacman -Syu'
alias py2='python2'
alias py3='python3'
alias s='sudo'
alias r='ranger'
alias r.='ranger --choosedir=$HOME/.rangerdir --cmd="set preview_files=true" "$(if [ -z "$@" ]; then cat $HOME/.rangerdir; fi)";cd "`cat $HOME/.rangerdir`"'
alias sr='sudo ranger --choosedir=$HOME/.rangerdir --cmd="set preview_files=true" "$(if [ -z "$@" ]; then cat $HOME/.rangerdir; fi)";cd "`cat $HOME/.rangerdir`"'
alias u='unp -U'
alias unp='unp -U'
alias create-readme='cp $HOME/.README.md ./README.md && nvim README.md'
alias sv='sudo -E nvim'
alias v='nvim'
alias vmutt='sudo -E vim $HOME/.muttrc'
alias E='emacs -nw'
# test .Xresources colors
alias testx='echo;for a in {40..47}; do echo -ne "\e[0;30;$a""m  ""\e[0;37;39m "; done; echo ""'
alias neofetch='neofetch --backend ascii --source /mnt/4ADE1465DE144C17/gdrive/nexor.ascii -L'
alias cutefetch='while true; do screenfetch_out="$(screenfetch -a $HOME/nexor.ascii -p)$(testx;echo;echo;echo)";sleep 1;clear;printf "$screenfetch_out"|lolcat;sleep 1; done'
alias screenfetch="screenfetch -a $HOME/nexor.ascii -p"
alias gfd='git fetch origin; git diff master'
alias gD='git diff HEAD HEAD~1'
alias gc='git clone'
unalias gr
function gr(){ fileh="$@"; git checkout $(git rev-list -n 1 HEAD -- "$@")~1 -- "$@" }
function gac(){ cm="${@:1}"; [[ -n "$cm" ]] || read "cm?Enter commit message: "; git add .; git commit -m "$cm"; }
function gacp(){ gac "${@:1}"; git push; }
#function gacdp(){ cm="${@:1}"; [[ -n "$cm" ]] || read "cm?Enter commit message: "; git add .; git commit -m "$cm"; gd; git push; }
function gdc(){ git diff HEAD HEAD~1; }
alias gs='git status'
alias gco='git checkout'
alias vp='nvim "$HOME/Dropbox/Sys4Bank - Programas Java/pendencias.txt"'
alias srm='sudo rm'
alias mkdir='mkdir -p'
# terminal geographic map
alias asciimap='telnet mapscii.me'
# tmux attach
alias ta='tmux a -t sess0'
alias smv='sudo mv'
alias msk='ncmpcpp'
alias cfa='sudo -E nvim $HOME/.bash_aliases'
#alias cfb='sudo -E nvim $HOME/.bashrc'
alias cfc='sudo -E nvim /home/nexor/mandragora/.dottyrc.json'
alias cfd='sh -c "cd $HOME/mandragora && git diff HEAD HEAD~1"'
alias cfe='sudo -E nvim $HOME/.emacs'
alias cfi='sudo -E nvim $HOME/.config/i3/config'
alias cfp='$HOME/mandragora/dotty/dotty.py -c -f -s'
alias cfP='ranger $HOME/.config/powerline/'
alias cfb='nvim $HOME/.config/polybar/config'
alias cfr='sudo -E nvim $HOME/.config/ranger'
alias cft='nvim $HOME/.tmux.conf'
alias cfv='sudo -E nvim $HOME/.config/nvim/init.vim'
alias cfV='sudo -E nvim $HOME/.config/nvim'
alias cfx='sudo -E nvim $HOME/.Xresources; xrdb $HOME/.Xresources'
alias cfz='sudo -E nvim $HOME/.zshrc'
alias motd='sudo cat /etc/update-motd.d/nexor.asc'
alias serve='python3 -m http.server 2717'
alias servetxt='xargs echo -e "HTTP/1.1 200 OK\r\n\r\n" | nc -l -p 2717 -c'
alias schmod='sudo chmod'
alias snode='sudo node'
alias sf='sudo find / -iname'
alias weather='curl wttr.in | head -n -1'
alias h='cd ..'
alias cd..='cd ..'
alias eye='tail -f'
alias ka='killall'
alias e='echo'
alias c='xsel -i -b'
alias co='xsel -o -b'
alias feh='feh -B black --scale-down --auto-zoom --sort mtime -. --action2 "rm %F" --action1 "realpath $PWD/%F | xsel -i -b"'
alias randip="dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tu1 | sed -e 's/^ *//' -e 's/  */./g'"
alias 2wmv='sudo ffmpeg -c:v wmv2 -b:v 99M -c:a wmav2 -b:a 192k output.wmv -i'
alias mp32wav='mpg123 -w output.wav'
alias o='xdg-open'
alias g='grep -i'
alias it='ps aux|head -n -1|grep '
alias prolog='swipl -q'
alias t='date +%s'
alias rsync='rsync -a --info=progress2'
# open in existing browser window
alias waterfox='[[ $(ps aux|grep -c waterfox) -eq 1 ]] && waterfox || waterfox -new-tab'
alias R='R --silent '
# alias mp42gif='mp4_file="$@"; mkdir -p animation_frames; ffmpeg -i "$mp4_file" -r 5 "animation_frames/frame-%03d.jpg"; convert -delay 20 -loop 0 animation_frames/*.jpg animation.gif; rm -r animation_frames'
alias acs='apt-cache search'
alias lisp='clisp --silent'
alias pa='ps aux|grep'
# alias jsonify='python -m json.tool --sort-keys'
alias jsonify='echo use jq instead /dev/stderr'

alias iftop='sudo iftop -Nlp'
alias cava='cava -p $HOME/.config/cava/config'
alias usdbrl='curl "http://free.currencyconverterapi.com/api/v5/convert?q=USD_BRL&compact=y" 2>&1 | re "\:(\d[^}]+)}" | e R\$ $(cat -)'
alias eurbrl='curl "http://free.currencyconverterapi.com/api/v5/convert?q=EUR_BRL&compact=y" 2>&1 | re "\:(\d[^}]+)}" | e R\$ $(cat -)'
alias btcbrl='curl "http://free.currencyconverterapi.com/api/v5/convert?q=BTC_BRL&compact=y" 2>&1 | re "\:(\d[^}]+)}" | e R\$ $(cat -)'
alias ali='apt list --installed'
alias alsao2i='pacmd set-default-source "alsa_output.pci-0000_00_1b.0.analog-stereo.monitor"'
alias alsai2i='pacmd set-default-source "alsa_input.pci-0000_00_1b.0.analog-stereo"'
alias alsawat='pacmd list-sources|grep -A 5 \* '
alias giquo='re "\"([^\"]+)"'
alias gipar='re "\(([^\)]+)"'
alias gip='re "((\d{1,3}\.){3}\d{1,3})"'
# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias cutecat='awk "{print $0; system(\"sleep .001\");}"'
#   text to speech:
function tts(){ printf "(SayText "`cat -`")" | festival -i;}
function vapor(){ vapore="`cat -`"; n=1;if [[ "$1" == "-n" ]]; then n=$2;fi;for i in {1..$n};do vapore="`echo $vapore | sed -r 's/(.)/\1 /g'`";done;echo $vapore; }
alias d='trash'
alias mbtc='/mnt/4ADE1465DE144C17/gdrive/Programming/bash/mbtc/alerter.sh'
alias rp='realpath -z'
# short whereis for scripting
function wis(){ whereis "$1" | cut -d':' -f2 | cut -d' ' -f2;}
alias reip='re "\d+\.\d+\.\d+\.\d+"'
alias ecdsa='ssh-keygen -l -f /etc/ssh/ssh_host_ecdsa_key.pub; ssh-keygen -l -f $_ -E md5'
alias up2pi='rsync -a "`pwd`" torta:'
# alias sumlines='python3 -c "import sys; print(eval("+".join(sys.stdin).replace("\n",""))"'
# alias backup='rsync -e "ssh -p 22" -avzp /home/nexor/kekao 25.25.25.25:'
function tf() { tail -f "$1" 2>&1 | perl -ne 'if (/file truncated/) {system 'clear'; print} else {print}'; }
function t2d(){ timestamp="`cat -`"; date -d "@$timestamp"; }
function knock(){ nc -z -w3 "$1" "$2"; echo $?; }
# exit code of arg
function ec() { [[ "$1" == "-h" ]] && { shift && eval $* > /dev/null 2>&1; ec=$?; echo $ec; } || eval $*; ec=$?; }
function sshasap(){ while [[ `nc -z -w1 "$1" 22` -gt 0 ]]; do sleep 1; done; beep ssh "$1"; }
# function copa(){ kek="$(curl -s http://worldcup.sfg.io/matches/current)"; echo -n $kek|jq '.[0].home_team.goals'|tr -d '\n'; echo -n 'x'; echo $kek|jq '.[0].away_team.goals'; }
alias diff='diff --color=auto'
alias fslint='/usr/share/fslint/fslint/fslint'
alias stream='pkill darkice; alsao2i; tmux new -d darkice'
# for real time READMEs editing:
alias grip='wmctrl -a waterfox && st -e tmux -c "stty -ixon && nvim *.md" & grip -b --wide'
function cdt(){ wis_smth="`wis "$1"`"; abs_path="`readlink -f "$wis_smth"`"; cd `dirname "$abs_path"`; }
alias filesize='du -h'
function addalias(){ echo "alias $1='${@:2}'" >> $HOME/.bash_aliases; }
function domany() { if [[ "$1" == "-n" ]]; then n=$2; else n=99999; fi; cmd="${@:3}"; for i in {1..$n}; do sh -c $cmd; done; }
function vw() { nvim "`whereis $1 | cut -d':' -f2 | cut -d' ' -f2;`"; }
function svw() { sudo -E nvim "`whereis $1 | cut -d':' -f2 | cut -d' ' -f2;`"; }
function wi(){ wal --saturate 1.0 -i "${@:1}"; }
alias biggest-files='du -hsx *|sudo sort -rh|head -10'
alias lg='lazygit'
alias pwdc="pwd | tr -d '\n' | xsel -i -b"
alias scrot='scrot ~/.scrot.png'
function f(){ sudo find . -iname "*$@*"; }
function cdf(){ cd `find . -iname "*$@*" | head -n1`; }
alias curpos="cnee --record --mouse | awk  '/7,4,0,0,1/ { system(\"xdotool getmouselocation\") }'"
alias p3u='pip3 uninstall'
alias p3u='pip3 uninstall'
alias p3i='pip3 install --user'
alias p2i='pip2 install --user'
alias p3r='pip3 uninstall'
alias p3r='pip2 uninstall'
function cnt() { echo $1 | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc {} -g -o "$noext" ${@:2} && clear && ./"$noext"'; }
function cntr() { echo $1 | entr echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc '${@:2}' {} -g -o "$noext" && clear && sh -c "$noext || :"'; }
function centr() { ls *.c* | entr echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc '$@' {} -g -o "$noext" && clear && exec "$noext"'; }
function pentr() { ls *.py* | entr /_ $@ }
function mentr() { ls *.* | entr "make clean; make" }
function N() { ls *.* | entr sh -c $@ }
alias dotty='. $HOME/mandragora/dotty/dotty.py'
alias mviz='ncmpcpp --screen visualizer'
function countdown(){ date1=$((`date +%s` + $1)); while [ "$date1" -ge `date +%s` ]; do clear; echo -ne "$(date -u --date @$(($date1 - `date +%s`)) +%H:%M:%S)\r" | figlet; sleep 0.1; done; }
function stopwatch(){ date1=`date +%s`; while true; do clear; echo -ne "$(date -u --date @$((`date +%s` - $date1)) +%H:%M:%S)\r" | figlet; sleep 0.1; done; }
alias sw='sudo wifi-menu'
alias cfs='ranger ~/util/st/ && cd $_ && sudo make install'
alias vtop='vtop -t seti'
function fortune() { re '\[(.+)\]' ".vim/bundle/vim-startify/autoload/startify/fortune.vim" | shuf | head -n2; }
function make-ranger-aliases(){ cat ~/.config/ranger/rc.conf | grep "^map g" | grep -v '\?' | grep cd | awk '{printf "alias g"$2"='\''"; $1=$2=""; print $0"'\''"}' | sed -E 's/\s{2}//g' > $HOME/.ranger_aliases; }
function ytdl(){ youtube-dl --extract-audio --audio-format "mp3" -o "/mnt/4ADE1465DE144C17/Musik/%(title)s.%(ext)s" $1; }
alias wt='watch -n 1 tree'
function wtg(){ watch -n 1 "tree | grep $@" }
alias wcat='watch -n 1 cat'
function hl(){ hamachi list | tail -n +2 | grep '^\s*\*' | awk '{print $4}'; }
function whl(){ watch -g "hamachi list | tail -n +2 | grep '^\s*\*' | awk '{print \$4}'" && beep -l 1000 }
function coif(){ fp="$@"; xclip -selection clipboard -t image/png -o > $fp && realpath -z $fp | xsel -i -b; }
function ocsv() { cat "$@" | psc -k -d, | `wis sc` }
alias sc='sc-im'
alias ov='vim'
function fv(){ find . -type f -name "*$@*" -exec nvim {} +  }
function zt(){ tar -czvf $1".tar.gz" ${@:2} }
function zz(){ zip -r  "$1".zip ${@:2} }
alias less='bat'
alias py='python'
alias S='du -sh'
alias gsu='git ls-files . --exclude-standard --others'
alias gsi='git ls-files . --ignored --exclude-standard --others'
alias sgdm='sudo gdmap -f .'
alias cfy='nvim /home/nexor/.vim/bundle/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py'
alias H='cd -'
alias piu='pip install --user'
alias lo='libreoffice'
alias jn='jupyter notebook'
alias wav2ogg='oggenc -q 3 -o file.ogg'
alias ogg2wav='ffmpeg -i audio.ogg audio.wav'
alias nudoku='nudoku -c'
function cdd(){ cd `dirname $1` }
alias pir='sudo pip uninstall'
alias scrot2imgur='curl -s -X POST --url https://api.imgur.com/3/image -H "Authorization: Client-ID $imgur_client_id" -F "image=@"$HOME/.scrot.png | jq -r '.data.link' | xsel -i -b'
alias 2048='/home/nexor/util/bash2048/bash2048.sh'
alias ws='watch stat'
function vf(){ find . -iname "*$@*" | head -n1 | xargs nvim  }
function vg(){ grep -ril "*$@*" | head -n1 | xargs nvim  }
alias vc='echo `xsel -o -b`|xargs nvim'
alias vC='echo `xclip -o`|nvim'
unalias gg
function gg(){ git grep "$@" $(git rev-list --all) }
alias nig='npm i -g'
alias tron='ssh sshtron.zachlatta.com'
alias empty-trash='rm -rf $HOME/.local/share/Trash/*'
alias fsw='fswatch .'
function isprime(){ if [[ $1 -eq 2 ]]||[[ $1 -eq 3 ]];then return 0;fi;if [[ $(($1 % 2)) -eq 0 ]]||[[ $(($1 % 3)) -eq 0 ]];then return 1;fi;i=5;w=2;while [[ $((i * i)) -le $1 ]];do if [[ $(($1 % i)) -eq 0 ]];then return 1;fi;i=$((i + w));w=$((6 - w));done;return 0; }
alias sdf='ssh mvrozanti@sdf.org'
alias wip='dig +short myip.opendns.com @resolver1.opendns.com'
alias ms='ssh play@anonymine-demo.oskog97.com -p 2222'
alias R='nnn'
alias googlecloud='gcloud compute --project projeto-cloud-226116 ssh --zone us-west1-b instance-1'
alias agi='sudo apt-get install'
alias agr='sudo apt-get remove'
alias tnsd='tmux new-session -d sh -c'
# alias ls='[ -x "$(command -v exa)" ] && exa || ls'
alias wdu='watch -n 1 du -sh "*"'
alias vh='nvim /home/nexor/.zsh_history'
alias make-gource-mandragora='git --no-pager log --date=raw|g "^\s+.+|Date"|sed -E "s/Date:\s+//g"|sed "N;s/\n//"|sed -E "s/(\S+)\s-\S+\s+(.+)/\1|\2/g" > caption_file'
alias tfl='tf *.log'
alias cfk='nvim /home/nexor/.config/kitty/kitty.conf'
alias cfK='nvim /home/nexor/.config/kitty/startup_session.kit'
alias ki='khal interactive'
alias sxiv='sxiv -a'
alias i='sxiv -ft *'
function hextv(){ while true; do kek=`head /dev/urandom|tr -dc A-Za-z0-9|head -c $1`;e $kek|xxd;sleep $2;done }
alias ci='cargo install'
unalias sd
alias cfrc='nvim $HOME/.config/ranger/rc.conf'
alias cfri='nvim $HOME/.config/ranger/rifle.conf'
alias cfrs='nvim $HOME/.config/ranger/scope.sh'
alias cfrd='nvim $HOME/.config/ranger/devicons.sh'
alias k='kitty'
function cfcf(){ trackedf=`realpath $1`; [[ $trackedf == $HOME* ]] && lefths=`echo $trackedf|xargs readlink -f|sd $HOME'/(.*)' '$1'` || lefths="${trackedf:1}"; jq '.copy |= . + {"'$lefths'":"'$([[ $trackedf == $HOME*  ]] && echo $trackedf|sd $HOME'(.*)' '~$1' || echo $trackedf)'"}' $HOME"/mandragora/.dottyrc.json" | sponge $HOME"/mandragora/.dottyrc.json" }
function cfci(){ jq '.install |= . + ["'$1'"]' ~/mandragora/.dottyrc.json | sponge ~/mandragora/.dottyrc.json }
# function cfcc(){ jq '.commands |= . + ["'$1'"]' ~/mandragora/.dottyrc.json | sponge ~/mandragora/.dottyrc.json }
function lnb(){ fpath="$1"; dst="$2"; sudo ln -s `realpath $fpath` /usr/local/bin/`[[ -z "$dst" ]] && echo $fpath|cut -f 1 -d '.' || echo $2` }
alias cfD='nvim /home/nexor/mandragora/dotty/dotty.py'
alias grow='[[ `git -C ~/mandragora pull|wc -l` -eq 1 ]] || ~/mandragora/dotty/dotty.py -f -r && git -C ~/mandragora submodule update --recursive --remote'
