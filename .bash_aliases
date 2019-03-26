unalias sd
alias rm='rm -f'
# alias ll='ls -alFh'
alias la='exa --all'
alias ls=exa
alias l='exa --reverse --sort=modified'
alias watch='watch --color -n2'
alias sps='sudo pacman -S'
alias spr='sudo pacman -Rns'
alias pss='pacman -Ss'
alias pqo='pacman -Qo'
alias spsyu='sudo pacman -Syu'
alias py2='python2'
alias py3='python3'
alias s='sudo'
alias r.='ranger'
alias r='ranger --choosedir=$HOME/.rangerdir --cmd="set preview_files=true" "$(if [ -z "$@" ]; then cat $HOME/.rangerdir; fi)";cd "`cat $HOME/.rangerdir`"'
alias sr='sudo ranger --choosedir=$HOME/.rangerdir --cmd="set preview_files=true" "$(if [ -z "$@" ]; then cat $HOME/.rangerdir; fi)";cd "`cat $HOME/.rangerdir`"'
alias u='unp -U'
alias unp='unp -U'
alias create-readme='cp $HOME/.README.md ./README.md && nvim README.md'
alias E='emacs -nw'
# test .Xresources colors
alias colors='echo;for a in {40..47}; do echo -ne "\e[0;30;$a""m  ""\e[0;37;39m "; done; echo ""'
alias neofetch='neofetch --backend ascii --source /mnt/4ADE1465DE144C17/gdrive/nexor.ascii -L'
alias cutefetch='while true; do screenfetch_out="$(screenfetch -a $HOME/nexor.ascii -p)$(testx;echo;echo;echo)";sleep 1;clear;printf "$screenfetch_out"|lolcat;sleep 1; done'
alias screenfetch="screenfetch -a $HOME/nexor.ascii -p"
alias gfd='git fetch origin; git diff master'
alias gD='git diff HEAD HEAD~1'
alias gc='git clone'
alias gmc='git merge --continue'
unalias gr
gr(){ fileh="$@"; git checkout $(git rev-list -n 1 HEAD -- "$@")~1 -- "$@" }
gac(){ cm="${@:1}"; [[ -n "$cm" ]] || read "cm?Enter commit message: "; git add .; git commit -m "$cm"; }
gacp(){ gac "${@:1}"; git push; }
#gacdp(){ cm="${@:1}"; [[ -n "$cm" ]] || read "cm?Enter commit message: "; git add .; git commit -m "$cm"; gd; git push; }
gdc(){ git diff HEAD HEAD~1; }
alias gs='git status'
alias gco='git checkout'
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
alias cfI='v ~/.irssi/config'
alias cfp='$HOME/mandragora/dotty/dotty.py -c -f -s'
alias cfP='ranger $HOME/.config/powerline/'
alias cfs='ranger ~/util/st/ && cd $_ && sudo make install'
alias cfS='v /home/nexor/.scimrc'
alias cfb='v $HOME/.config/polybar/config'
alias cfr='sudo -E nvim $HOME/.config/ranger'
alias cft='v $HOME/.tmux.conf'
alias cfv='sudo -E nvim $HOME/.config/nvim/init.vim'
alias cfV='sudo -E nvim $HOME/.config/nvim'
alias cfx='sudo -E nvim $HOME/.Xresources; xrdb $HOME/.Xresources'
alias cfz='sudo -E nvim $HOME/.zshrc'
alias cfy='v /home/nexor/.vim/bundle/YouCompleteMe/third_party/ycmd/.ycm_extra_conf.py'
alias cfk='v /home/nexor/.config/kitty/kitty.conf'
alias motd='sudo cat /etc/update-motd.d/nexor.asc'
alias serve='python3 -m http.server 2717'
alias servetxt='xargs echo -e "HTTP/1.1 200 OK\r\n\r\n" | nc -l -p 2717 -c'
alias schmod='sudo chmod'
alias snode='sudo node'
alias sf='sudo find / -iname'
alias weather='curl -s wttr.in | head -n -1'
alias h='cd ..'
alias hh='h;h'
alias cd..='cd ..'
alias eye='tail -f'
alias ka='killall'
alias e='echo'
alias c='xsel -i -b'
alias co='xsel -o -b'
alias cow='co | xargs wget'
alias cov='co | xargs nvim'
alias cogc='[[ -d .git ]] && git submodule add `co` || git clone `co`'
# alias P='curl -sF "sprunge=<-" http://sprunge.us'
alias P='curl -sF "f:1=<-" ix.io'
# P(){ curl  -X POST -d @- http://0x0.st }
alias p='P | c'
alias feh='feh -B black --scale-down --auto-zoom --sort mtime -. --action2 "rm %F" --action1 "realpath $PWD/%F | xsel -i -b"'
alias randip="dd if=/dev/urandom bs=4 count=1 2>/dev/null | od -An -tu1 | sed -e 's/^ *//;s/  */./g'"
alias 2wmv='sudo ffmpeg -c:v wmv2 -b:v 99M -c:a wmav2 -b:a 192k output.wmv -i'
alias mp32wav='mpg123 -w output.wav'
o(){ nohup xdg-open $@ 2>&1 >/dev/null & }
O(){ nohup xdg-open $@ 2>&1 >/dev/null &; exit }
alias g='grep -i'
alias it='ps aux|head -n -1|grep '
alias prolog='swipl -q'
alias T='date +%s'
alias t='tree'
alias rsync='rsync -a --info=progress2'
# open in existing browser window
alias waterfox='[[ $(ps aux|grep -c waterfox) -eq 1 ]] && waterfox || waterfox -new-tab'
alias R='R --silent '
mp42gif(){ mp4_file="$@"; mkdir -p animation_frames; ffmpeg -i "$mp4_file" -r 5 "animation_frames/frame-%03d.jpg"; convert -delay 20 -loop 0 animation_frames/*.jpg animation.gif; rm -r animation_frames }
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
# alias backup='rsync -e "ssh -p 22" -avzp /home/nexor/kekao 25.25.25.25:'
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
aa(){ [[ ! -z $1 && ! -z $2 ]] && echo "alias $1='${@:2}'" >> $HOME/.bash_aliases; }
domany() { if [[ "$1" == "-n" ]]; then n=$2; else n=99999; fi; cmd="${@:3}"; for i in {1..$n}; do sh -c $cmd; done; }
vw() { nvim "`whereis $1 | cut -d':' -f2 | cut -d' ' -f2;`"; }
svw() { sudo -E nvim "`whereis $1 | cut -d':' -f2 | cut -d' ' -f2;`"; }
wi(){ wal --saturate 1.0 -i "${@:1}"; }
alias biggest-files='du -hsx *|sudo sort -rh|head -10'
alias lg='lazygit'
alias pwdc="pwd | tr -d '\n' | xsel -i -b"
alias scrot='scrot ~/.scrot.png'
# f(){ sudo find . -iname "*$@*"; }
cdf(){ cd `find . -iname "*$@*" | head -n1`; }
alias curpos="cnee --record --mouse | awk  '/7,4,0,0,1/ { system(\"xdotool getmouselocation\") }'"
alias p3u='pip3 uninstall'
alias p3u='pip3 uninstall'
alias p3i='pip3 install --user'
alias p2i='pip2 install --user'
alias p3r='pip3 uninstall'
alias p3r='pip2 uninstall'
cnt(){ echo $1 | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc {} -g -o "$noext" ${@:2} && clear && ./"$noext"'; }
cntr(){ echo $1 | entr echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc '${@:2}' {} -g -o "$noext" && clear && sh -c "$noext || :"'; }
bentr(){ ls * | entr -p /_ $@ }
centr(){ ls *.c | entr -r echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; gcc '$@' {} -g -o "$noext" && clear && exec "$noext"'; }
gentr(){ ls *.cpp | entr -r echo /_ | xargs -I{} sh -c 'noext="`echo {}|cut -d. -f1`"; g++ '$@' {} -o "$noext" && clear && exec "$noext"'; }
pentr(){ [[ -z $1 ]] && ls *.py* | entr -rc /_ $@ || echo $1 | entr /_ }
mentr(){ ls *.* | entr make }
xentr(){ ls *.* | entr -p $@ /_ }
nentr(){ ls *.* | entr -p $@ node /_ }
ventr(){ [[ $(($#)) -gt 0 ]] && ls | entr -r sh -c 'valgrind --quiet --show-leak-kinds=all --leak-check=full '`realpath ${@: -1}`' -v --track-origins=yes' }
alias entr='entr -p'
alias dotty='$HOME/mandragora/dotty/dotty.py'
alias mviz='ncmpcpp --screen visualizer'
countdown(){ date1=$((`date +%s` + $1)); while [ "$date1" -ge `date +%s` ]; do clear; echo -ne "$(date -u --date @$(($date1 - `date +%s`)) +%H:%M:%S)\r" | figlet; sleep 0.1; done; }
stopwatch(){ date1=`date +%s`; while true; do clear; echo -ne "$(date -u --date @$((`date +%s` - $date1)) +%H:%M:%S)\r" | figlet; sleep 0.1; done; }
alias sw='sudo wifi-menu'
alias vtop='vtop -t seti'
alias sv='sudo -E nvim'
alias v='nvim'
alias vc='co|v -'
alias vh='nvim /home/nexor/.zsh_history'
vx(){ xxd $@ | v - }
make-ranger-aliases(){ cat ~/.config/ranger/rc.conf | grep "^map g" | grep -v '\?' | grep cd | awk '{printf "alias g"$2"='\''"; $1=$2=""; print $0"'\''"}' | sed -E 's/\s{2}//g' > $HOME/.ranger_aliases; }
ytdl(){ youtube-dl --extract-audio --audio-format "mp3" -o "/mnt/4ADE1465DE144C17/Musik/%(title)s.%(ext)s" $1; }
alias wt='watch -n 1 tree'
wtg(){ watch -n 1 "tree | grep $@" }
alias wcat='watch -n 1 cat'
hl(){ hamachi list | sed -E '/\*/!d;/\s{2,}\*/!d;s/\s+\*\S+?\s+?\S+?\s+?(\S+)\s+(\S+).+$/\1 \2/g' }
whl(){ watch "hamachi list | sed -E '/\*/!d;/\s{2,}\*/!d;s/\s+\*\S+?\s+?\S+?\s+?(\S+)\s+(\S+).+$/\1 \2/g'" }
coif(){ fp="$@"; xclip -selection clipboard -t image/png -o > $fp && realpath -z $fp | xsel -i -b; }
ocsv() { cat "$@" | psc -k -d, | `wis sc` }
alias sc='sc-im'
fv(){ find . -type f -name "*$@*" -exec nvim {} +  }
zt(){ tar -czvf $1".tar.gz" ${@:2} }
zz(){ [[ "$#" -eq 2 ]] && zip -r  "$1".zip ${@:2} }
alias less='bat'
alias py='python'
alias S='du -sh'
alias gsu='git ls-files . --exclude-standard --others'
alias gsi='git ls-files . --ignored --exclude-standard --others'
gdm(){ [[ $# -eq 0 ]] && gdmap -f . || gdmap -f "$@" }
sgdm(){ [[ $# -eq 0 ]] && sudo gdmap -f . || sudo gdmap -f "$@" }
alias H='cd -'
alias piu='pip install --user'
alias lo='libreoffice'
alias jn='jupyter notebook'
alias wav2ogg='oggenc -q 3 -o file.ogg'
alias ogg2wav='ffmpeg -i audio.ogg audio.wav'
alias nudoku='nudoku -c'
cdd(){ cd `dirname $1` }
alias pir='sudo pip uninstall'
up2imgur(){ curl -s -X POST --url https://api.imgur.com/3/image -H "Authorization: Client-ID $imgur_client_id" -F "image=@$@" }
up2giphy(){ curl -s -X POST --url https://upload.giphy.com/v1/gifs -H "api_key: $giphy_client_id" -F "file=@$@" | jq .data.id |xargs -i echo https://i.giphy.com/media/{}/source.gif }
up2gfycat(){ [[ -z $1 ]] && return || { json_data=`curl -s -XPOST https://api.gfycat.com/v1/gfycats`; [[ `echo $json_data|jq .isOk` ]] || return ; gfyname=`echo $json_data|jq -r .gfyname`; secret=`echo $json_data|jq .secret`; cp $1 /tmp/$gfyname; curl -s -i https://filedrop.gfycat.com --upload-file /tmp/$gfyname 2>&1 >/dev/null; echo https://gfycat.com/$gfyname } }
alias 2048='/home/nexor/util/bash2048/bash2048.sh'
alias ws='watch stat'
vf(){ find . -iname "*$@*" | head -n1 | xargs nvim  }
vg(){ grep -ril "*$@*" | head -n1 | xargs nvim  }
unalias gg
gg(){ git grep "$@" $(git rev-list --all) }
alias nig='npm i -g'
alias tron='ssh sshtron.zachlatta.com'
alias empty-trash='rm -rf $HOME/.local/share/Trash/*'
alias fsw='fswatch .'
isprime(){ if [[ $1 -eq 2 ]]||[[ $1 -eq 3 ]];then return 0;fi;if [[ $(($1 % 2)) -eq 0 ]]||[[ $(($1 % 3)) -eq 0 ]];then return 1;fi;i=5;w=2;while [[ $((i * i)) -le $1 ]];do if [[ $(($1 % i)) -eq 0 ]];then return 1;fi;i=$((i + w));w=$((6 - w));done;return 0; }
alias sdf='ssh mvrozanti@sdf.org'
alias wip='dig +short myip.opendns.com @resolver1.opendns.com'
alias ms='ssh play@anonymine-demo.oskog97.com -p 2222'
alias R='nnn'
alias googlecloud='gcloud compute --project projeto-cloud-226116 ssh --zone us-east1-b instance-2'
alias agi='sudo apt-get install'
alias agr='sudo apt-get remove'
alias tnsd='tmux new-session -d sh -c'
# alias ls='[ -x "$(command -v exa)" ] && exa || ls'
alias wdu='watch -n 1 du -sh "*"'
alias lh='less /home/nexor/.zsh_history'
alias make-gource-mandragora='git --no-pager log --date=raw|g "^\s+.+|Date"|sed -E "s/Date:\s+//g"|sed "N;s/\n//"|sed -E "s/(\S+)\s-\S+\s+(.+)/\1|\2/g" > caption_file'
alias tfl='tf *.log'
alias cfK='nvim /home/nexor/.config/kitty/startup_session.kit'
alias ki='khal interactive'
alias sxiv='sxiv -ab'
alias i='sxiv -ft *'
hextv(){ while true; do kek=`head /dev/urandom|tr -dc A-Za-z0-9|head -c $1`;e $kek|xxd;sleep $2;done }
alias cfrc='nvim $HOME/.config/ranger/rc.conf'
alias cfri='nvim $HOME/.config/ranger/rifle.conf'
alias cfrs='nvim $HOME/.config/ranger/scope.sh'
alias cfrd='nvim $HOME/.config/ranger/devicons.sh'
alias k='kitty'
# cfcr(){ trackedf=`realpath $1`; [[ $trackedf == $HOME* ]] && lefths=`echo $trackedf|xargs readlink -f|sd $HOME'/(.*)' '$1'` || lefths="${trackedf:1}"; jq '.copy |= . + {"'$lefths'":"'$([[ $trackedf == $HOME*  ]] && echo $trackedf|sd $HOME'(.*)' '~$1' || echo $trackedf)'"}' $HOME"/mandragora/.dottyrc.json" | sponge $HOME"/mandragora/.dottyrc.json" }
cfcf(){ trackedf=`realpath $1`; [[ $trackedf == $HOME* ]] && lefths=`echo $trackedf|xargs readlink -f|sd $HOME'/(.*)' '$1'` || lefths="${trackedf:1}"; jq '.copy |= . + {"'$lefths'":"'$([[ $trackedf == $HOME*  ]] && echo $trackedf|sd $HOME'(.*)' '~$1' || echo $trackedf)'"}' $HOME"/mandragora/.dottyrc.json" | sponge $HOME"/mandragora/.dottyrc.json" }
cfcu(){ to_remove="$1"; [[ ! -z $to_remove ]] && removed_array="`jq '.install|map(select(.!="'$to_remove'"))' $HOME"/mandragora/.dottyrc.json"`" && jq .install="$removed_array" $HOME"/mandragora/.dottyrc.json" | sponge ~/mandragora/.dottyrc.json }
cfci(){ jq '.install |= . + ["'$1'"]' ~/mandragora/.dottyrc.json | sponge ~/mandragora/.dottyrc.json }
lnb(){ le_fpath="$1"; le_dst="$2"; sudo ln -s `realpath $le_fpath` ~/.local/bin/`[[ -z "$le_dst" ]] && echo $le_fpath|cut -f 1 -d '.' || echo $2` }
alias cfD='nvim /home/nexor/mandragora/dotty/dotty.py'
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
alias sctl='sudo systemctl'
alias GD='git daemon --base-path=. --export-all'
alias blank='xset -display :0.0 dpms force off'
setbg(){ [[ -z $1 ]] && return 1; fpath=`realpath $1` ; [[ `echo $fpath | rev | cut -d"." -f1 | rev` = "gif" ]] && xwinwrap -g `xrandr | awk '/\*/{printf $1" "}'` -ni -s -nf -b -un -argb -ov -- gifview -w WID $fpath -a || wal -a 299 -i $fpath }
ra(){ [[ ! -z "$1" && ! -z "$2" ]] && sd -i 'alias '$1'=' 'alias '$2'=' $HOME/.bash_aliases && sd -i ''$1'\(\)' ''$2'()' $HOME/.bash_aliases }
alias I='uname -mrs'
alias spsyyu='sudo pacman -Syyu'
alias fuck='sudo'
alias scan4sd='echo 1 | sudo tee /sys/bus/pci/rescan'
alias sj='sudo journalctl'
onf(){ inotifywait -m . -e create -e moved_to | while read pathe action filet; do echo $filet | xargs -I{} $@; done }
alias netbeans='/usr/bin/netbeans'
alias lasagna='countdown "11*60" && for i in {1..4}; do beep -l 500; sleep 0.5; done'
alias clock='watch -t -n1 "date +"%H:%M"|figlet -f big"'
alias cfn='v ~/.newsboat/config'
alias cfN='v ~/.newsboat/urls'
alias N='newsboat'
arf(){ echo "$@" >> ~/.newsboat/urls }
alias help='echo no && read'
alias t1='tail -n1'
alias t1a='t1 /home/nexor/.bash_aliases'
alias sl='ls'
alias cfT='v /home/nexor/.tig'
alias burncd='i3-msg workspace 1 && o https://www.linuxquestions.org/questions/linux-newbie-8/how-to-burn-files-into-a-dvd-from-command-line-4175464968/'
alias enc='openssl aes-256-cbc -in - 2>/dev/null'
alias dec='enc -d 2>/dev/null'
alias scrot2imgur2cb='up2imgur $HOME/.scrot.png | c'
hue(){ [[ -z $1 || -z $2 ]] && {echo kek && return} || cp $1 hue_000;  for i in $(seq 1 50); do convert hue_000 -modulate 100,100,-$(($i*4)) hue_$(printf "%03d\n" $i);  done;  echo creating gif; rm hue_000; nice -20 convert -limit memory 4GB -limit map 4GB -define registry:temporary-path=/var/tmp -loop 0 -delay 1 hue_* $2; rm hue_* };
ncp(){ [[ -z $1 ]] && echo kek || { md -p $1; cd $1; dotnew new console -o $1; dotnet new sln; dotnet sln add $1/$1.csproj } }
alias cfZ='v /home/nexor/.config/zathura/zathurarc'
alias cfm='v /home/nexor/.config/mutt/muttrc'
alias leet='toilet -d ~/.config/figlet -f rusto'
alias playback='pacat -r | aplay -c 2 -f S16_LE -r 44100'
divsil(){ [[ -z $@ ]] && return; jq -r '.'`echo $@|cut -c1`'."'$@'"' < ~/prog/python/portal-da-lingua-portuguesa/palavras-divisao-silabica.json }
alias sanduba='countdown "6*60" && for i in {1..4}; do beep -l 500; sleep 0.5; done'
alias hlo='hamachi logout'
alias hli='hamachi login'
ti(){ tar -czf - $@ > ~/.tarchive.tar }
to(){ tar -xzv < ~/.tarchive.tar }
compv(){ co | xargs mpv }
alias scanlan='nmap -p80,443 192.168.0.0/24 -oG -'
alias scanvuln='nikto -h -'
alias pull='git pull'
ytpl(){ search="$@"; mpv --script-opts=ytdl_hook-try_ytdl_first=yes ytdl://ytsearch:"$search" }
alias sk='screenkey --font-color red --opacity 0.2 --compr-cnt 3 -s small'
alias U='sudo umount'
alias cfM='v .config/mpv/input.conf'
alias mp='jmtpfs ~/phone'
alias sp='rsync -rtv /mnt/4ADE1465DE144C17/Musik "/home/nexor/phone/Internal storage/Music"'
alias ve='v -c "let startify_disable_at_vimenter = 1" '
alias V=ve
alias vi=ve
alias howtomake='o http://www.cs.colby.edu/maxwell/courses/tutorials/maketutor/'
alias jflap='java -jar ~/mackenzie/2019/compiladores/JFLAP.jar'
lix(){ curl -s ix.io/user/ | grep '<a href=' |sed 1q | sd -f m '.+?href=.(.+?).>.+' '$1' | xargs -I{} curl -s ix.io{} }
alias spscc='s pacman -Scc'
alias wmd5='watch md5sum'
alias re='perl -pe'
wco(){ watch xsel -o -b }
v.(){ v . }
alias cfC='v /home/nexor/.config/nvim/coc-settings.json'
alias G='googler -l en -n 3 -c en'
coytdl(){ ytdl `co` }
alias /f='/;f'
alias copss='pss `co`'
_toggle_ssh_password_auth(){ grep 'PasswordAuthentication yes' /etc/ssh/sshd_config >/dev/null; [[ $? -eq 0 ]] && sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config || sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config; sudo systemctl restart sshd; trap - SIGINT }
wetty(){ _toggle_ssh_password_auth; trap _toggle_ssh_password_auth SIGINT; node ~/util/wetty/index.js -p 2717 }
alias xfix='xset r rate 200 30;xmodmap ~/.Xmodmap;setxkbmap us alt-intl'
toggle_touchpad(){ [[ `xinput list-props 12 | grep "Device Enabled" | grep -o "[01]$"` -eq 1 ]] && xinput --disable 12 || xinput --enable 12 }
alias cocd='cd `co`'
alias cocdd='cdd `co`'
other_mndrgr(){ [[ `hostname` == "mndrgr" ]] && echo mndrgr2 || echo mndrgr }
diffmndrgr(){ [[ -z $@ ]] || diff $@ <(ssh $(other_mndrgr) 'cat '$(realpath $@)) }
alias cosv='sv `co`'
alias cos='sudo `co`'
alias corm='rm `co`'
mdcd(){ md $@; cd $_ }
