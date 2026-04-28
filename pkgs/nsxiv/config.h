#ifdef INCLUDE_WINDOW_CONFIG

static const int WIN_WIDTH  = 800;
static const int WIN_HEIGHT = 600;

static const char *WIN_BG[]   = { "Nsxiv.window.background",   "#0E0E0E" };
static const char *WIN_FG[]   = { "Nsxiv.window.foreground",   "#EEEEEE" };
static const char *MARK_FG[]  = { "Nsxiv.mark.foreground",      NULL };
#if HAVE_LIBFONTS
static const char *BAR_BG[]   = { "Nsxiv.bar.background",       "#111111" };
static const char *BAR_FG[]   = { "Nsxiv.bar.foreground",       "#EEEEEE" };
static const char *BAR_FONT[] = { "Nsxiv.bar.font",            "monospace:size=8" };

static const bool TOP_STATUSBAR = false;
#endif

#endif
#ifdef INCLUDE_IMAGE_CONFIG

static const float zoom_levels[] = {
	 12.5,  25.0,  50.0,  75.0,
	100.0, 150.0, 200.0, 400.0, 800.0
};

static const int SLIDESHOW_DELAY = 1;

static const int    CC_STEPS        = 32;
static const double GAMMA_MAX       = 10.0;
static const double BRIGHTNESS_MAX  = 2.0;
static const double CONTRAST_MAX    = 4.0;

static const int PAN_FRACTION = 5;

static const int CACHE_SIZE_MEM_PERCENTAGE = 3;
static const int CACHE_SIZE_LIMIT = 256 * 1024 * 1024;
static const int CACHE_SIZE_FALLBACK = 32 * 1024 * 1024;

#endif
#ifdef INCLUDE_OPTIONS_CONFIG

static const bool ANTI_ALIAS = true;
static const bool ALPHA_LAYER = false;
static const char TNS_FILTERS[] = "";
static const bool TNS_FILTERS_IS_BLACKLIST = false;

#endif
#ifdef INCLUDE_THUMBS_CONFIG

static const int thumb_sizes[] = { 32, 64, 96, 128, 160 };
static const int THUMB_SIZE = 3;

#endif
#ifdef INCLUDE_MAPPINGS_CONFIG

static const unsigned int USED_MODMASK = ShiftMask | ControlMask | Mod1Mask;
static const KeySym KEYHANDLER_ABORT = XK_Escape;

static const keymap_t keys[] = {
	/* modifiers    key               function              argument */
	{ 0,            XK_q,             g_quit,               0 },
	{ 0,            XK_Q,             g_pick_quit,          0 },
	{ 0,            XK_Return,        g_switch_mode,        None },
	{ 0,            XK_f,             g_toggle_fullscreen,  None },
	{ 0,            XK_B,             g_toggle_bar,         None },
	{ ControlMask,  XK_x,             g_prefix_external,    None },
	{ 0,            XK_0,             g_first,              None },
	{ 0,            XK_dollar,        g_n_or_last,          None },
	{ 0,            XK_r,             g_reload_image,       None },
	{ 0,            XK_D,             g_remove_image,       None },
	{ ControlMask,  XK_h,             g_scroll_screen,      DIR_LEFT },
	{ ControlMask,  XK_Left,          g_scroll_screen,      DIR_LEFT },
	{ ControlMask,  XK_j,             g_zoom,               -1 },
	{ ControlMask,  XK_Down,          g_scroll_screen,      DIR_DOWN },
	{ ControlMask,  XK_k,             g_zoom,               +1 },
	{ ControlMask,  XK_Up,            g_scroll_screen,      DIR_UP },
	{ ControlMask,  XK_l,             g_scroll_screen,      DIR_RIGHT },
	{ ControlMask,  XK_Right,         g_scroll_screen,      DIR_RIGHT },
	{ 0,            XK_plus,          g_zoom,               +1 },
	{ 0,            XK_KP_Add,        g_zoom,               +1 },
	{ 0,            XK_KP_Subtract,   g_zoom,               -1 },
	{ 0,            XK_m,             g_toggle_image_mark,  None },
	{ 0,            XK_M,             g_mark_range,         None },
	{ ControlMask,  XK_m,             g_reverse_marks,      None },
	{ ControlMask,  XK_u,             g_unmark_all,         None },
	{ 0,            XK_N,             g_navigate_marked,    +1 },
	{ 0,            XK_P,             g_navigate_marked,    -1 },
	{ 0,            XK_braceleft,     g_change_gamma,       -1 },
	{ 0,            XK_braceright,    g_change_gamma,       +1 },
	{ ControlMask,  XK_g,             g_change_gamma,        0 },

	{ 0,            XK_h,             t_move_sel,           DIR_LEFT },
	{ 0,            XK_Left,          t_move_sel,           DIR_LEFT },
	{ 0,            XK_j,             t_move_sel,           DIR_DOWN },
	{ 0,            XK_Down,          t_move_sel,           DIR_DOWN },
	{ 0,            XK_k,             t_move_sel,           DIR_UP },
	{ 0,            XK_Up,            t_move_sel,           DIR_UP },
	{ 0,            XK_l,             t_move_sel,           DIR_RIGHT },
	{ 0,            XK_Right,         t_move_sel,           DIR_RIGHT },
	{ 0,            XK_R,             t_reload_all,         None },

	{ 0,            XK_w,             i_navigate,           +1 },
	{ 0,            XK_w,             i_scroll_to_edge,     DIR_LEFT | DIR_UP },
	{ 0,            XK_space,         i_navigate,           +1 },
	{ 0,            XK_b,             i_navigate,           -1 },
	{ 0,            XK_b,             i_scroll_to_edge,     DIR_LEFT | DIR_UP },
	{ 0,            XK_BackSpace,     i_navigate,           -1 },
	{ 0,            XK_bracketright,  i_navigate,           +10 },
	{ 0,            XK_bracketleft,   i_navigate,           -10 },
	{ ControlMask,  XK_6,             i_alternate,          None },
	{ ControlMask,  XK_n,             i_navigate_frame,     +1 },
	{ ControlMask,  XK_p,             i_navigate_frame,     -1 },
	{ ControlMask,  XK_space,         i_toggle_animation,   None },
	{ 0,            XK_h,             i_scroll,             DIR_LEFT },
	{ 0,            XK_Left,          i_scroll,             DIR_LEFT },
	{ 0,            XK_j,             i_scroll,             DIR_DOWN },
	{ 0,            XK_Down,          i_scroll,             DIR_DOWN },
	{ 0,            XK_k,             i_scroll,             DIR_UP },
	{ 0,            XK_Up,            i_scroll,             DIR_UP },
	{ 0,            XK_l,             i_scroll,             DIR_RIGHT },
	{ 0,            XK_Right,         i_scroll,             DIR_RIGHT },
	{ 0,            XK_H,             i_scroll_to_edge,     DIR_LEFT },
	{ 0,            XK_J,             i_scroll_to_edge,     DIR_DOWN },
	{ 0,            XK_K,             i_scroll_to_edge,     DIR_UP },
	{ 0,            XK_L,             i_scroll_to_edge,     DIR_RIGHT },
	{ 0,            XK_y,             i_copy_to_clipboard,  None },
	{ 0,            XK_equal,         i_fit_to_win,         SCALE_DOWN },
	{ 0,            XK_plus,          i_fit_to_win,         SCALE_WIDTH },
	{ 0,            XK_minus,         i_fit_to_win,         SCALE_HEIGHT },
	{ 0,            XK_s,             i_fit_to_win,         SCALE_FIT },
	{ 0,            XK_less,          i_rotate,             DEGREE_270 },
	{ 0,            XK_greater,       i_rotate,             DEGREE_90 },
	{ 0,            XK_question,      i_rotate,             DEGREE_180 },
	{ 0,            XK_bar,           i_flip,               FLIP_HORIZONTAL },
	{ 0,            XK_underscore,    i_flip,               FLIP_VERTICAL },
	{ 0,            XK_a,             i_toggle_antialias,   None },
	{ 0,            XK_A,             i_toggle_alpha,       None },
	{ 0,            XK_S,             i_slideshow,          None },
};

static const button_t buttons_img[] = {
	/* modifiers    button            function              argument */
	{ 0,            1,                i_cursor_navigate,    None },
	{ ControlMask,  1,                i_drag,               DRAG_RELATIVE },
	{ 0,            2,                i_drag,               DRAG_ABSOLUTE },
	{ 0,            3,                g_switch_mode,        None },
	{ 0,            4,                g_zoom,               +1 },
	{ 0,            5,                g_zoom,               -1 },
};

static const button_t buttons_tns[] = {
	/* modifiers    button            function              argument */
	{ 0,            1,                t_select,             None },
	{ 0,            3,                t_drag_mark_image,    None },
	{ 0,            4,                t_scroll,             DIR_UP },
	{ 0,            5,                t_scroll,             DIR_DOWN },
	{ ControlMask,  4,                g_scroll_screen,      DIR_UP },
	{ ControlMask,  5,                g_scroll_screen,      DIR_DOWN },
};

static const bool NAV_IS_REL = true;
static const unsigned int NAV_WIDTH = 33;

static const cursor_t imgcursor[3] = {
	CURSOR_LEFT, CURSOR_ARROW, CURSOR_RIGHT
};

#endif
