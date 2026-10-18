import app from "ags/gtk4/app"
import GLib from "gi://GLib"
import { monitorFile, readFile } from "ags/file"

const paletteFile = GLib.getenv("MANDRAGORA_SHELL_PALETTE") ??
  `${GLib.get_user_cache_dir()}/matugen/colors-ags.css`

const fallback = `
@define-color surface #191112;
@define-color surface_container_lowest #140c0d;
@define-color surface_container_low #22191a;
@define-color surface_container #261d1e;
@define-color surface_container_high #312829;
@define-color surface_container_highest #3c3233;
@define-color on_surface #f0dee0;
@define-color on_surface_variant #d6c2c3;
@define-color outline #9f8c8e;
@define-color outline_variant #524345;
@define-color primary #ffb2bd;
@define-color on_primary #561d29;
@define-color primary_container #72333f;
@define-color on_primary_container #ffd9dd;
@define-color secondary #e5bdc1;
@define-color on_secondary #43292d;
@define-color secondary_container #5c3f43;
@define-color on_secondary_container #ffd9dd;
@define-color tertiary #eabf8f;
@define-color on_tertiary #452b07;
@define-color tertiary_container #5e411c;
@define-color on_tertiary_container #ffddb9;
@define-color error #ffb4ab;
@define-color on_error #690005;
@define-color error_container #93000a;
@define-color on_error_container #ffdad6;
@define-color shadow #000000;
@define-color scrim #000000;
`

function palette(): string {
  try {
    return readFile(paletteFile)
  } catch {
    return ""
  }
}

export function applyTheme(style: string) {
  const load = () => app.apply_css(fallback + palette() + style, true)
  load()
  let pending = 0
  monitorFile(paletteFile, () => {
    if (pending) GLib.source_remove(pending)
    pending = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 250, () => {
      pending = 0
      load()
      return GLib.SOURCE_REMOVE
    })
  })
}
