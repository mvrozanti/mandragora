unalias sd
unalias sp
alias rm='rm -f'
# alias ll='ls -alFh'
alias lt='ls -snew'
alias la='exa --all'
alias ls=exa
alias l='exa --reverse --sort=modified'
alias watch='watch --color -n1 --no-title'
alias sps='sudo pacman -S'
alias spr='sudo pacman -Rns'
alias pss='pacman -Ss'
alias pqo='pacman -Qo'
alias spsyu='sudo pacman -Syu'
alias py='ptpython --vi'
alias s='sudo'
alias r.='ranger'
r(){ ranger --choosedir=$HOME/.rangerdir --cmd="set preview_files=true";cd "`cat $HOME/.rangerdir`" }
alias sr='sudo ranger --choosedir=~/.rangerdir --cmd="set preview_files=true" "$(if [ -z "$@" ]; then cat ~/.rangerdir; fi)";cd "`cat ~/.rangerdir`"'
alias u='unp -U'
alias unp='unp -U'
alias create-readme='cp ~/.README.md ./README.md && nvim README.md'
alias E='emacs -nw'
# test .Xresources colors
alias showcolors='echo;for a in {40..47}; do echo -ne "\e[0;30;$a""m  ""\e[0;37;39m "; done; echo ""'
# alias neofetch='neofetch --backend ascii --source /mnt/4ADE1465DE144C17/gdrive/nexor.ascii'
alias cutefetch='while true; do screenfetch_out="$(screenfetch -a ~/nexor.ascii -p)$(colors;echo;echo;echo)";sleep 1;clear;printf "$screenfetch_out"|lolcat;sleep 1; done'
alias screenfetch="screenfetch -a ~/nexor.ascii -p"
alias gfd='git fetch origin; git diff master'
alias gc='git clone'
alias gmc='git merge --continue'
unalias gr
gr(){ fileh="$@"; git checkout $(git rev-list -n 1 HEAD -- "$@")~1 -- "$@" }
#gacdp(){ cm="${@:1}"; [[ -n "$cm" ]] || read "cm?Enter commit message: "; git add .; git commit -m "$cm"; gd; git push; }
gdc(){ git diff HEAD HEAD~1; }
alias gs='git status'
alias gco='git checkout'
alias srm='sudo rm'
alias mkdir='mkdir -p'
# terminal geographic map
alias asciimap='telnet mapscii.me'
# tmux attach
alias ta='task add'
alias smv='sudo mv'
alias msk='ncmpcpp'
alias cfa='sudo -E nvim ~/.bash_aliases'
#alias cfb='sudo -E nvim ~/.bashrc'
alias cfc='sudo -E nvim ~/mandragora/.dottyrc.json'
alias cfd='sh -c "cd ~/mandragora && git diff HEAD HEAD~1"'
alias cfe='sudo -E nvim ~/.emacs'
alias cfi='sudo -E nvim ~/.config/i3/config'
alias cfI='v ~/.irssi/config'
alias cfp='~/mandragora/dotty/dotty.py -c -f -s'
# alias cfP='ranger ~/.config/powerline/'
alias cfP='v ~/.config/ncmpcpp/'
alias cfs='ranger ~/util/st/ && cd $_ && sudo make install'
alias cfS='v ~/.scimrc'
alias cfb='v ~/.config/polybar/config'
alias cfr='v ~/.config/ranger'
alias cft='v ~/.tmux.conf'
alias cfv='nvim ~/.config/nvim/init.vim'
alias cfV='sudo nvim -u NORC ~/.config/nvim'
alias cfx='sudo nvim -u NORC ~/.Xresources; xrdb ~/.Xresources'
alias cfz='sudo -E nvim ~/.zshrc'
alias cfy='v ~/.vim/bundle/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py'
alias cfk='v ~/.config/kitty/kitty.conf'
alias motd='cat /etc/motd'
alias serve='python3 -m http.server 2717'
alias servetxt='xargs echo -e "HTTP/1.1 200 OK\r\n\r\n" | nc -l -p 2717 -c'
alias schmod='sudo chmod'
alias snode='sudo node'
alias sf='sudo find / -iname'
alias weather='curl -s wttr.in | head -n -1'
alias h='cd ..'
alias hh='h;h'
alias cd..='cd ..'
alias ka='killall'
alias e='echo'
alias c='xsel -i -b'
alias co='xsel -o -b'
alias cow='co | xargs wget'
alias cov='co | xargs nvim'
alias cogc='[[ -d .git ]] && git submodule add `co` || git clone `co`; cd `rev <(co) | cut -d '/' -f1 | rev`'
# alias P='curl -sF "sprunge=<-" http://sprunge.us'
alias P='curl -sF "f:1=<-" ix.io'
# P(){ curl  -X POST -d @- http://0x0.st }
alias p='P | c'
alias feh='feh -B black --scale-down --auto-zoom --sort mtime -. --action2 "rm %F" --action1 "realpath $PWD/%F | xsel -i -b"'
alias randip="dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tu1 | sed -e 's/^ *//;s/  */./g'"
myip(){ curl -s ipinfo.io | jq '.ip' | tr -d '"' }
alias 2wmv='sudo ffmpeg -c:v wmv2 -b:v 99M -c:a wmav2 -b:a 192k output.wmv -i'
alias mp32wav='mpg123 -w output.wav'
o(){ nohup xdg-open $@ 2>&1 >/dev/null & }
O(){ nohup xdg-open $@ 2>&1 >/dev/null &; exit }
alias g='grep -i --color '
alias swipl='swipl -q'
alias prolog='swipl'
alias T='date +%s'
alias t='tree'
alias rsync='rsync -a --info=progress2'
# open in existing browser window
alias waterfox='[[ $(ps aux|grep -c waterfox) -eq 1 ]] && waterfox || waterfox -new-tab'
alias R='R --silent '
alias acs='apt-cache search'
alias lisp='clisp --silent'
alias pa='ps aux|grep'
# alias jsonify='python -m json.tool --sort-keys'
alias jsonify='echo use jq instead /dev/stderr'
alias iftop='sudo iftop -Nlp'
alias cava='cava -p ~/.config/cava/config'
alias usdbrl='curl "http://free.currencyconverterapi.com/api/v5/convert?q=USD_BRL&compact=y" 2>&1 | re "\:(\d[^}]+)}" | e R\$ $(cat -)'
alias eurbrl='curl "http://free.currencyconverterapi.com/api/v5/convert?q=EUR_BRL&compact=y" 2>&1 | re "\:(\d[^}]+)}" | e R\$ $(cat -)'
alias btcbrl='curl "http://free.currencyconverterapi.com/api/v5/convert?q=BTC_BRL&compact=y" 2>&1 | re "\:(\d[^}]+)}" | e R\$ $(cat -)'
alias ali='apt list --installed'
alias alsao2i='pacmd set-default-source "alsa_output.pci-0000_00_1b.0.analog-stereo.monitor"'
alias alsai2i='pacmd set-default-source "alsa_input.pci-0000_00_1b.0.analog-stereo"'
alias alsawat='pacmd list-sources|grep -A 5 \* '
# alias giquo='re "\"([^\"]+)"'
# alias gipar='re "\(([^\)]+)"'
# alias gip='re "((\d{1,3}\.){3}\d{1,3})"'
# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias cutecat='awk "{print $0; system(\"sleep .001\");}"'
#   text to speech:
tts(){ printf "(SayText "`cat -`")" | festival -i;}
vapor(){ vapore="`cat -`"; n=1;if [[ "$1" == "-n" ]]; then n=$2;fi;for i in {1..$n};do vapore="`echo $vapore | sed -r 's/(.)/\1 /g'`";done;echo $vapore; }
alias d='trash'
alias mbtc='/mnt/4ADE1465DE144C17/gdrive/Programming/bash/mbtc/alerter.sh'
alias rp='realpath -z'
# short whereis for scripting
wis(){ whereis "$1" | cut -d':' -f2 | cut -d' ' -f2;}
# alias reip='re "\d+\.\d+\.\d+\.\d+"'
alias ecdsa='ssh-keygen -l -f /etc/ssh/ssh_host_ecdsa_key.pub; ssh-keygen -l -f $_ -E md5'
alias up2pi='rsync -a "`pwd`" torta:'
# alias sumlines='python3 -c "import sys; print(eval("+".join(sys.stdin).replace("\n",""))"'
# alias backup='rsync -e "ssh -p 22" -avzp ~/kekao 25.25.25.25:'
tf() { tail -f "$1" 2>&1 | perl -ne 'if (/file truncated/) {system 'clear'; print} else {print}'; }
t2d(){ timestamp="`cat -`"; date -d "@$timestamp"; }
knock(){ nc -z -w3 "$1" "$2"; echo $?; }
# exit code of arg
ec() { [[ "$1" == "-h" ]] && { shift && eval $* > /dev/null 2>&1; ec=$?; echo $ec; } || eval $*; ec=$?; }
sshasap(){ while [[ `nc -z -w1 "$1" 22` -gt 0 ]]; do sleep 1; done; beep ssh "$1"; }
# copa(){ kek="$(curl -s http://worldcup.sfg.io/matches/current)"; echo -n $kek|jq '.[0].home_team.goals'|tr -d '\n'; echo -n 'x'; echo $kek|jq '.[0].away_team.goals'; }
alias diff='diff --color=auto'
alias fslint='/usr/share/fslint/fslint/fslint'
alias stream='pkill darkice; alsao2i; tmux new -d darkice'
# for real time READMEs editing:
alias grip='wmctrl -a waterfox && st -e tmux -c "stty -ixon && nvim *.md" & grip -b --wide'
cdt(){ wis_smth="`wis "$1"`"; abs_path="`readlink -f "$wis_smth"`"; cd `dirname "$abs_path"`; }
alias filesize='du -h'
aa(){ [[ ! -z $1 && ! -z $2 ]] && echo "alias $1='${@:2}'" >> ~/.bash_aliases; }
domany() { if [[ "$1" == "-n" ]]; then n=$2; else n=99999; fi; cmd="${@:3}"; for i in {1..$n}; do sh -c $cmd; done; }
vw() { nvim "`whereis $1 | cut -d':' -f2 | cut -d' ' -f2;`"; }
svw() { sudoedit"`whereis $1 | cut -d':' -f2 | cut -d' ' -f2;`"; }
wi(){ wal --saturate 1.0 -i "${@:1}"; }
alias biggest-files='du -hsx *|sudo sort -rh|head -10'
alias lg='lazygit'
alias pwdc="pwd | tr -d '\n' | xsel -i -b"
alias scrot='scrot ~/.scrot.png'
# f(){ sudo find . -iname "*$@*"; }
cdf(){ cd `find . -iname "*$@*" | head -n1`; }
alias curpos="cnee --record --mouse | awk  '/7,4,0,0,1/ { system(\"xdotool getmouselocation\") }'"
alias p3u='pip3 uninstall'
alias p3i='pip3 install --user'
alias p2i='pip2 install --user'
alias p3r='pip3 uninstall'
alias p3r='pip2 uninstall'
alias nvimdiff='nvim -d'
alias vimdiff=nvimdiff
alias entr='entr -p'
cnt(){ echo $1 | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc {} -g -o "$noext" ${@:2} && clear && ./"$noext"'; }
xentr(){ ls * | entr -p /_ $@ }
cntr(){ echo $1 | entr echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc '${@:2}' {} -g -o "$noext" && clear && sh -c "$noext || :"'; }
centr(){ ls *.c   | entr -r echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc '"$@"' {} -g -o "$noext" && clear && exec "$noext"'; }
gentr(){ ls *.cpp | entr -r echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; g++ '$@' {} -g -o "$noext" && clear && exec "$noext"'; }
# pentr(){ [[ -z $1 ]] && ls *.py* | entr -rc /_ $@ || echo $1 | entr /_ }
mentr(){ ls | entr -c make }
mxentr(){ ls *.c   | entr -r echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; make && clear && exec "$noext"'; }
jentr(){ ls *.java | entr -c javac * }
nentr(){ ls *.* | entr $@ node /_ }
prentr(){ ls *.pl | entr $@ swipl -q /_ }
xdentr(){ le_f1="$1"; le_f2="$2"; ls *.* | entr nvim -d <(xxd $le_f1) <(xxd $le_f2) }
ventr(){ [[ $(($#)) -gt 0 ]] && echo $1 | entr -cr sh -c 'valgrind --quiet --show-leak-kinds=all --leak-check=full '`realpath ${@: -1}`' -v --track-origins=yes' }
alias dotty='~/mandragora/dotty/dotty.py'
alias mviz='ncmpcpp --screen visualizer'
countdown(){ date1=$((`date +%s` + $1)); while [ "$date1" -ge `date +%s` ]; do clear; echo -ne "$(date -u --date @$(($date1 - `date +%s`)) +%H:%M:%S)\r" | figlet; sleep 0.1; done; }
stopwatch(){ date1=`date +%s`; while true; do clear; echo -ne "$(date -u --date @$((`date +%s` - $date1)) +%H:%M:%S)\r" | figlet; sleep 0.1; done; }
alias sw='sudo wifi-menu'
alias vtop='vtop -t seti'
alias sv='sudoedit'
alias v='nvim'
alias vc='co | v -'
alias cv='cov'
alias vh='nvim ~/.zsh_history'
vx(){ xxd $@ | v - }
make-ranger-aliases(){ cat ~/.config/ranger/rc.conf | grep "^map g" | grep -v '\?' | grep cd | awk '{printf "alias z"substr($2, 2)"='\''"; $1=$2=""; print substr($0, 1)"'\''"}' | sed -E 's/\s{2}//g' > ~/.ranger_aliases; }
ytdl(){ youtube-dl --extract-audio --audio-format "mp3" -o "/mnt/4ADE1465DE144C17/Musik/%(title)s.%(ext)s" $@; }
alias wt='watch -n 1 tree'
wtg(){ watch -n 1 "tree | grep $@" }
wcat(){ ls "$@" | entr -c cat /_ }
hl(){ hamachi list | sed -E '/\*/!d;/\s{2,}\*/!d;s/\s+\*\S+?\s+?\S+?\s+?(\S+)\s+(\S+).+$/\1 \2/g' }
whl(){ watch "hamachi list | sed -E '/\*/!d;/\s{2,}\*/!d;s/\s+\*\S+?\s+?\S+?\s+?(\S+)\s+(\S+).+$/\1 \2/g'" }
coif(){ fp="$@"; xclip -selection clipboard -t image/png -o > $fp && realpath -z $fp | xsel -i -b; }
ocsv() { cat "$@" | psc -k -d, | `wis sc` }
alias sc='sc-im'
fv(){ find . -type f -name "*$@*" -exec nvim {} +  }
Zt(){ tar -czvf $1".tar.gz" ${@:2} }
Zz(){ [[ "$#" -eq 2 ]] && zip -r  "$1".zip ${@:2} }
alias S='du -sh'
alias gsu='git ls-files . --exclude-standard --others'
alias gsi='git ls-files . --ignored --exclude-standard --others'
gdm(){ [[ $# -eq 0 ]] && gdmap -f . || gdmap -f "$@" }
sgdm(){ [[ $# -eq 0 ]] && sudo gdmap -f . || sudo gdmap -f "$@" }
alias H='cd -'
alias piu='pip install --user'
alias lo='libreoffice 2>&1 > /dev/null &'
alias jn='jupyter notebook'
alias wav2ogg='oggenc -q 3 -o file.ogg'
alias ogg2wav='ffmpeg -i audio.ogg audio.wav'
alias nudoku='nudoku -c'
cdd(){ cd `dirname $1` }
alias pir='pip uninstall --no-cache-dir'
up2imgur(){ curl -s -X POST --url https://api.imgur.com/3/image -H "Authorization: Client-ID $imgur_client_id" -F "image=@$@" | jq -r .data.link }
up2giphy(){ curl -s -X POST --url https://upload.giphy.com/v1/gifs -H "api_key: $giphy_client_id" -F "file=@$@" | jq .data.id |xargs -i echo https://i.giphy.com/media/{}/source.gif }
up2gfycat(){ [[ -z $1 ]] && return || { json_data=`curl -s -XPOST https://api.gfycat.com/v1/gfycats`; [[ `echo $json_data|jq .isOk` ]] || return ; gfyname=`echo $json_data|jq -r .gfyname`; secret=`echo $json_data|jq .secret`; cp $1 /tmp/$gfyname; curl -s -i https://filedrop.gfycat.com --upload-file /tmp/$gfyname 2>&1 >/dev/null; echo https://gfycat.com/$gfyname } }
alias 2048='~/util/bash2048/bash2048.sh'
alias ws='watch stat'
vf(){ find . -iname "*$@*" | head -n1 | xargs nvim  }
vg(){ grep -ril "*$@*" | head -n1 | xargs nvim  }
unalias gg
gg(){ git grep "$@" $(git rev-list --all) }
alias nig='npm i -g'
alias tron='ssh sshtron.zachlatta.com'
alias empty-trash='rm -rf ~/.local/share/Trash/*'
alias fsw='fswatch .'
isprime(){ if [[ $1 -eq 2 ]]||[[ $1 -eq 3 ]];then return 0;fi;if [[ $(($1 % 2)) -eq 0 ]]||[[ $(($1 % 3)) -eq 0 ]];then return 1;fi;i=5;w=2;while [[ $((i * i)) -le $1 ]];do if [[ $(($1 % i)) -eq 0 ]];then return 1;fi;i=$((i + w));w=$((6 - w));done;return 0; }
alias sdf='ssh mvrozanti@sdf.org'
# alias ms='ssh play@anonymine-demo.oskog97.com -p 2222'
alias ms=anonymine
alias R='nnn'
alias googlecloud='gcloud compute --project projeto-cloud-226116 ssh --zone us-east1-b instance-2'
alias agi='sudo apt-get install'
alias agr='sudo apt-get remove'
alias tnsd='tmux new-session -d sh -c'
# alias ls='[ -x "$(command -v exa)" ] && exa || ls'
alias wdu='watch -n 1 du -sh "*"'
alias lh='less ~/.zsh_history'
alias make-gource-mandragora='git --no-pager log --date=raw|g "^\s+.+|Date"|sed -E "s/Date:\s+//g"|sed "N;s/\n//"|sed -E "s/(\S+)\s-\S+\s+(.+)/\1|\2/g" > caption_file'
alias tfl='tf *.log'
alias cfK='nvim ~/.config/kitty/startup_session.kit'
alias ki='kitty'
alias sxiv='sxiv -ab 2>&1 >/dev/null'
alias i='sxiv -ft *'
hextv(){ while true; do kek=`head /dev/urandom|tr -dc A-Za-z0-9|head -c $1`;e $kek|xxd;sleep $2;done }
alias cfrc='nvim ~/.config/ranger/rc.conf'
alias cfri='nvim ~/.config/ranger/rifle.conf'
alias cfrs='nvim ~/.config/ranger/scope.sh'
alias cfrd='nvim ~/.config/ranger/devicons.sh'
alias k='khal interactive'
# cfcr(){ trackedf=`realpath $1`; [[ $trackedf == ~* ]] && lefths=`echo $trackedf|xargs readlink -f|sd ~'/(.*)' '$1'` || lefths="${trackedf:1}"; jq '.copy |= . + {"'$lefths'":"'$([[ $trackedf == ~*  ]] && echo $trackedf|sd ~'(.*)' '~$1' || echo $trackedf)'"}' ~"/mandragora/.dottyrc.json" | sponge ~"/mandragora/.dottyrc.json" }
cfcf(){ trackedf=`realpath $1`; [[ $trackedf == $HOME* ]] && lefths=`echo $trackedf|xargs readlink -f|sd $HOME'/(.*)' '$1'` || lefths="${trackedf:1}"; jq '.copy |= . + {"'$lefths'":"'$([[ $trackedf == $HOME*  ]] && echo $trackedf|sd $HOME'(.*)' '~$1' || echo $trackedf)'"}' $HOME"/mandragora/.dottyrc.json" | sponge $HOME"/mandragora/.dottyrc.json" }
cfcu(){ to_remove="$1"; [[ ! -z $to_remove ]] && removed_array="`jq '.install|map(select(.!="'$to_remove'"))' ~"/mandragora/.dottyrc.json"`" && jq .install="$removed_array" ~"/mandragora/.dottyrc.json" | sponge ~/mandragora/.dottyrc.json }
cfci(){ jq '.install |= . + ["'$1'"]' ~/mandragora/.dottyrc.json | sponge ~/mandragora/.dottyrc.json }
lnb(){ [[ $# != 2 ]] && return 1; le_fpath="$1"; le_dst="$2"; sudo ln -s `realpath $le_fpath` ~/.local/bin/`[[ -z "$le_dst" ]] && echo $le_fpath|cut -f 1 -d '.' || echo $2` }
alias cfD='sh -c "cd ~/mandragora && git diff"'
alias grow='[[ `git -C ~/mandragora pull|wc -l` -eq 1 ]] || ~/mandragora/dotty/dotty.py -f -r && git -C ~/mandragora submodule update --recursive --remote'
alias oc='mpv /dev/video0'
alias f='fd -H'
alias nohup='nohup > /dev/null'
alias SV='ffmpeg -f video4linux2  -i /dev/video0  -vcodec libx264 -preset fast -b 1000k -f matroska -y /dev/stdout | nc -lp 2717'
alias SA='pacat -r | nc -l -p 2718'
alias RA='nc `[[ $(hostname) == mndrgr2 ]] && echo mndrgr || echo mndrgr2` 2718 | aplay -c 2 -f S16_LE -r 44100'
alias RV='nc mndrgr2 2717 | mpv - -cache 512'
alias wS='watch du -sh'
servesingle(){ [[ ! -z $1 ]] && { filepath=`realpath $1` &&  echo -ne "HTTP/1.0 200 OK\r\nContent-Disposition: filename=\"`basename $filepath`\"\nContent-Length: $(wc -c <$filepath)\r\n\r\n"; cat $filepath; } | nc -l -p 2717 }
alias sS='servesingle'
alias ctl='systemctl'
alias sctl='sudo systemctl'
alias GD='git daemon --base-path=. --export-all' # serve git repo on port 9418
unalias gd
gd(){ [[ "$#" -eq 1 ]] && git diff HEAD~$@ || git diff }
alias gdd='git diff HEAD~1'
alias gddd='git diff HEAD~2'
alias gdddd='git diff HEAD~3'
alias gddddd='git diff HEAD~4'
alias blank='xset -display :0.0 dpms force off'
# setbg(){ [[ -z $1 ]] && return 1; fpath=`realpath $1` ; [[ `echo $fpath | rev | cut -d"." -f1 | rev` = "gif" ]] && xwinwrap -g `xrandr | awk '/\*/{printf $1" "}'` -ni -s -nf -b -un -argb -ov -- gifview -w WID $fpath -a || wal -a 299 -i $fpath }
ra(){ [[ ! -z "$1" && ! -z "$2" ]] && sd -i 'alias '$1'=' 'alias '$2'=' ~/.bash_aliases && sd -i ''$1'\(\)' ''$2'()' ~/.bash_aliases }
alias me='uname -mrs'
alias spsyyu='sudo pacman -Syyu'
alias fuck='sudo'
alias scan4sd='echo 1 | sudo tee /sys/bus/pci/rescan'
alias sj='sudo journalctl'
onf(){ inotifywait -m . -e create -e moved_to | while read pathe action filet; do echo $filet | xargs -I{} $@; done }
alias netbeans='/usr/bin/netbeans'
alias lasagna='countdown "11*60" && for i in {1..4}; do beep -l 400; sleep 0.6; done'
alias clock='watch -t -n1 "date +"%H:%M"|figlet -f big"'
alias cfn='v ~/.newsboat/config'
alias cfN='v ~/.newsboat/urls'
alias N='newsboat'
arf(){ echo "$@" >> ~/.newsboat/urls }
alias help='echo no && read'
alias t1='tail -n1'
alias t1a='t1 ~/.bash_aliases'
alias sl='slack'
alias cfT='v ~/.tig'
alias burncd='i3-msg workspace 1 && o https://www.linuxquestions.org/questions/linux-newbie-8/how-to-burn-files-into-a-dvd-from-command-line-4175464968/'
alias enc='openssl aes-256-cbc -in - 2>/dev/null'
alias dec='enc -d 2>/dev/null'
alias scrot2imgur2cb='up2imgur ~/.scrot.png | c'
hue(){ [[ -z $1 || -z $2 ]] && {echo kek && return} || cp $1 hue_000;  for i in $(seq 1 50); do convert hue_000 -modulate 100,100,-$(($i*4)) hue_$(printf "%03d\n" $i);  done;  echo creating gif; rm hue_000; nice -20 convert -limit memory 4GB -limit map 4GB -define registry:temporary-path=/var/tmp -loop 0 -delay 1 hue_* $2; rm hue_* };
ncp(){ [[ -z $1 ]] && echo kek || { md -p $1; cd $1; dotnew new console -o $1; dotnet new sln; dotnet sln add $1/$1.csproj } }
alias cfZ='v ~/.config/zathura/zathurarc'
alias cfm='v ~/.config/mutt/muttrc'
alias cfmu='v ~/.config/ncmpcpp/'
alias leet='toilet -d ~/.config/figlet -f rusto'
alias playback='pacat -r | aplay -c 2 -f S16_LE -r 44100'
divsil(){ [[ -z $@ ]] && return; jq -r '.'`echo $@|cut -c1`'."'$@'"' < ~/prog/python/portal-da-lingua-portuguesa/palavras-divisao-silabica.json }
alias sanduba='countdown "6*60" && for i in {1..3}; do beep -l 300; sleep 0.3; done'
alias hlo='hamachi logout'
alias hli='hamachi login'
ti(){ tar -czf - $@ > ~/.tarchive.tar }
to(){ tar -xzv < ~/.tarchive.tar }
compv(){ co | xargs mpv --ytdl-format=best }
alias scanlan='nmap -p80,443 192.168.0.0/24 -oG -'
alias scanvuln='nikto -h -'
alias pull='git pull'
ytpl(){ search="$@"; mpv --script-opts=ytdl_hook-try_ytdl_first=yes ytdl://ytsearch:"$search" }
alias yts='ytpl'
alias sk='screenkey --font-color red --opacity 0.2 --compr-cnt 3 -s small'
alias U='sudo umount'
alias cfM='v ~/.config/mpv/'
alias mp='jmtpfs ~/phone'
alias ve='v -c "let startify_disable_at_vimenter = 1" '
alias V=ve
alias vi=ve
alias howtomake='o http://www.cs.colby.edu/maxwell/courses/tutorials/maketutor/'
lix(){ curl -s ix.io/user/ | grep '<a href=' |sed 1q | sd -f m '.+?href=.(.+?).>.+' '$1' | xargs -I{} curl -s ix.io{} }
alias spscc='s pacman -Scc'
alias wmd5='watch md5sum'
alias re='perl -pe'
wco(){ watch xsel -o -b }
v.(){ v . }
alias cfC='v ~/.config/nvim/coc-settings.json'
alias G='googler -l en -n 3 -c en'
coy(){ ytdl `co` }
alias /f='/;f'
alias copss='pss `co`'
_toggle_ssh_password_auth(){ grep 'PasswordAuthentication yes' /etc/ssh/sshd_config >/dev/null; [[ $? -eq 0 ]] && sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config || sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config; sudo systemctl restart sshd; trap - SIGINT }
wetty(){ _toggle_ssh_password_auth; trap _toggle_ssh_password_auth SIGINT; node ~/util/wetty/index.js -p 2717 }
xfix(){ xmodmap ~/.Xmodmap; xset r rate 200 30; setxkbmap us alt-intl }
toggle_touchpad(){ [[ `xinput list-props 12 | grep "Device Enabled" | grep -o "[01]$"` -eq 1 ]] && xinput --disable 12 || xinput --enable 12 }
alias cocd='cd `co`'
alias cocdd='cdd `co`'
other_mndrgr(){ [[ `hostname` == "mndrgr" ]] && echo mndrgr2 || echo mndrgr }
diffmndrgr(){ [[ -z $@ ]] || diff $@ <(ssh $(other_mndrgr) 'cat '$(realpath $@)) }
alias cosv='sv `co`'
alias cos='sudo `co`'
alias corm='rm `co`'
mdcd(){ md $@; cd $_ }
alias enhance='function ne() { docker run --rm -v "$(pwd)/`dirname ${@:$#}`":/ne/input -it alexjc/neural-enhance ${@:1:$#-1} "input/`basename ${@:$#}`"; }; ne'
alias gaca='git add .; git commit --amend'
alias gacap='gaca; git push -f'
alias up='sudo umount ~/phone'
smp(){ diff <(ls ~/Musik/) <(ls "$HOME/phone/Internal storage/Music/") | grep mp3 | cut -c 3- | while read line; do line="/mnt/4ADE1465DE144C17/Musik/$line"; cp "$line" "$HOME/phone/Internal storage/Music/"; done }
spp(){ mv "~/phone/Internal storage/DCIM/Facebook/*" "~/phone/Internal storage/Pictures/Telegram/*" "~/phone/Internal storage/Pictures/Reddit/*" "~/phone/Internal storage/DCIM/Camera/*" ~/gdrive/Levv/4chan/ }
sp(){ smp;spp }
cox(){ `co` }
sa(){ grep -E "^(alias )?$@(=|\()" ~/.bash_aliases }
sma(){ sa "$@" | sd "alias.+='(.+)'|.+\(\)\{\s?(.+)\s?}" '$1$2' }
alias I='sxiv'
alias x='xargs'
alias coag='ag `co`'
alias pqi='pacman -Qi'
xdiff(){ [[ "$#" -eq 2 ]] && nvimdiff <(xxd $1) <(xxd $2) }
ca(){ le_line="$(sa $@)"; new_line="`echo $le_line | vipe`"; sd -s -i "`echo $le_line`" "`echo $new_line`" ~/.bash_aliases }
alias wstat='watch stat'
alias md5='md5sum'
alias lesss='less'
gC(){ git config pack.threads 1;git config pack.deltaCacheSize 1;git config core.packedGitWindowSize 16m;git config core.packedGitLimit 128m;git config pack.windowMemory 512mgit gc;git gc --aggressive;git prune }
alias tls='task list'
td(){ [[ -z $@ ]] || task $@ delete }
af(){ [[ "$#" -eq 2 ]] && echo "$1(){ ${@:2} }" >> ~/.bash_aliases || [[ "$#" -eq 1 ]] && echo "$1(){ <+> }" | vipe >> ~/.bash_aliases }
alias vig='v .gitignore'
x2c(){ printf "\\$(printf '%03o' "$1")" }
alias rp.c='realpath . | c'
alias vm='[[ -f CMakeLists.txt ]] && v CMakeLists.txt || v Makefile'
alias vcm='v CMakeLists.txt'
alias xlx='f -tnew | x file | g ELF | sed 1q | cut -d ":" -f1 | x -I{} zsh -c ./{}'
# xentr(){ ls | entr zsh -c 'setopt expand_aliases && source ~/.bash_aliases ; xlx' }
alias costat='co | x stat'
preent(){ clear;e $@ | leet | lolcat;read }
ren(){ e $@ | vipe | xargs -I{} mv $@ {} }
gource2mp4(){ gource -1280x720 -o - | ffmpeg -y -r 60 -f image2pipe -vcodec ppm -i - -vcodec libx264 -preset ultrafast -pix_fmt yuv420p -crf 1 -threads 0 -bf 0 $(basename `realpath .`) }
alias vre='v README.md'
wiki(){ `wis wiki` $@ | ww -w $COLUMNS }
alias screenkey='screenkey --font-color red --opacity 0.5 --compr-cnt 3 -s small'
alias trc='transmission-remote-cli'
alias cfpa='git --git-dir=$HOME/mandragora/.git commit --amend; git push'
cogacp(){ gacp "`co`" }
cosrm(){ srm "`co`" }
alb(){ ln -s "`realpath $1`" "$HOME/.local/bin/`basename -- $1`" }
alias scv='s `cv`'
sinon(){ ~/.local/bin/sinon $@ | ww -w $(($COLUMNS-3)) }
alias cocp='cp "`co`"'
alias wl='watch ls'
nem(){ nemo $@ 3>&2 2>&1 > /dev/null & }
alias schown='s chown'
alias cint='picoc'
wf(){ watch fd -H $@ }
alias piup='pip install --upgrade pip'
alias vres='v /home/nexor/mackenzie/2019/mpc/tex/simd.bib '
funccount(){ nm $@ | grep "T " | g -v " _" | wc -l }
urldecode(){ e "$@" | awk -niord '{printf RT?$0chr("0x"substr(RT,2)):$0}' RS=%.. }
oldf(){ ls -rsnew ~/Downloads | sed q1 | xargs -I{} xdg-open ~/Downloads/{} }
Oldf(){ ls -rsnew ~/Downloads | sed q1 | xargs -I{} `sma sxiv` ~/Downloads/{} }
alias lwcl='l | wc -l'
alias sum='python -c "import sys; print(sum(float(l) for l in sys.stdin))"'
cC(){ trap "exit" INT; while :; do [[ ! -z `co` ]] && co | "$@" && e -n | c; done }
alias rmr='rm -r'
alias zres='z tcc1/resources'
alias pk='pkill'
alias getredir='curl -Ls -o /dev/null -w %{url_effective}'
alias slns='s ln -s'
alias cocurl='co | xargs curl -s'
alias /ag='cd /;ag'
alias ns='notify-send'
alias torb='nohup tor-browser 2>&1 > /dev/null &'
keep(){ while :; do "$@"; done }
cowv(){ cow 2>&1 | grep to: | sd '.+‘(.+)’' '$1' | xargs nvim }
alias rp.='realpath .'
alias zresr='zres;r'
alias zat='zathura'
alias cu='curl'
alias tremc='sctl status transmission.service || sctl start transmission.service;transmission-remote-cli'
coz(){ wget -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/61.0.3163.100 Safari/537.36' "`co`" -O /tmp/html.pdf 2>&1 >/dev/null ; [[ "`file -ib /tmp/html.pdf`" =~ ".*pdf.*" ]] || cat $_ | wkhtmltopdf - $_ ; nohup zathura $_ 2>&1 >/dev/null & }
alias wla='watch ls -a'
alias 2h='hh'
cowat(){ co > /tmp/cowat.html ; waterfox --new-tab /tmp/cowat.html }
alias cocurll='cocurl | less'
trentr(){ e .travis.yml | entr echo /_ | xargs -I{} sh -c 'clear && travis lint {}' }
alias wag='watch ag'
alias f.='find .'
pentr(){ find . | entr -c sh -c 'ag "__name__ == '"'"'__main__'"'"'" | sed 1q | cut -d '"'"':'"'"' -f1 | xargs python' }
alias wls='watch ls'
alias cosxiv='sxiv `co`'
alias cogco='gco fix-non-existing-docker-image'
alias ag='ag --search-binary --hidden'
alias vt='v .travis.yml'
alias lc='history | tail -n1 | cut -d " " -f4'
alias schmxlc='schmod +x "`lc`"'
alias pytest='pytest -s'
ptentr(){ f "\\.py" | entr -c pytest --cov-report term-missing --cov=`basename $(pwd)` -s test*/*.py }
rpc(){ realpath $@ | c }
alias pie.='pip install -e .'
alias le='less'
alias cm='offlineimap-notify'
up2pypi(){ rm -r dist || : ; python setup.py bdist_wheel && twine upload dist/* }
unalias gbd
gbd(){ git branch -d "$@" && git push origin --delete "$@" }
alias gsc='git stash clear'
alias gsc='git stash clear'
alias gsa='git stash apply'
filter-colors(){ grep -oE '#[0-9A-F]{6}' | sed 1q }
alias hhh='2h;h'
dbt(){ docker build -t $@ . } # docker build tag
alias ds='docker stats'
alias drmi='docker rmi'
alias cormr='co | xargs rm -r'
alias 3h='hh;h'
aka(){ cat /etc/hosts | grep "$@" | cut -d' ' -f1 }
co/f(){ /f `co` }
alias mvncas='mvn clean compile assembly:single'
alias wh='watch head'
unalias gpf
alias gpf='git push -f'
alias gpsu='git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD)'
alias gri='git rebase -i'
alias wll='watch ls -lh'
alias wmd5.='watch md5sum *'
alias cd/='/'
alias gcfd='git clean -f -d'
alias co2i='xclip -selection clipboard -t image/png -o > clipboard-out.png'
alias co2imgur='xclip -selection clipboard -t image/png -o > /tmp/img; up2imgur /tmp/img'
alias v-='v -'
alias gddv-='gdd|v-'
alias coytdl='youtube-dl `co`'
