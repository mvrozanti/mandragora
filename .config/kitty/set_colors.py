from kitty.cmds import set_colors, get_colors
from kitty.config import parse_config
from kitty.constants import config_dir
from kitty.rgb import color_as_int, Color
import os

def main(args):
    pass

def handle_result(args, data, target_window_id, boss):
    # f = open('/home/nexor/kek', 'w')
    # print = lambda x: os.system('notify-send ' + str(x))
    colors = get_colors(boss, boss.window_id_map.get(target_window_id), { 'match':'background', 'configured': True })
    # print = lambda x: f.write(x+'\n'); f.flush()
    bg = fg = None
    for col_tuple in colors.split('\n'):
        while '  ' in col_tuple:
            col_tuple = col_tuple.replace('  ', ' ')
        k,v = col_tuple.split(' ')
        if k == 'background': bg = v
        if k == 'foreground': fg = v

    import random
    coin = random.randint(0,2) % 2 == 0
    print(str(coin))
    le_new_colors = {
            'background': -1 if coin else 0,
            'foreground':  0 if coin else -1
            }

    set_colors_opts = { 
            'all': False, 
            'match_window': False, 
            'match_tab': False, 
            'reset': False, 
            'configured': False, 
            'colors': le_new_colors 
            }
    set_colors(boss, boss.window_id_map.get(target_window_id), set_colors_opts)

handle_result.no_ui = True

if __name__ == '__main__':
    import sys
    main(sys.argv)
