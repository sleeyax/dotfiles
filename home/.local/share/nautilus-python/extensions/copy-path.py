import subprocess

from gi.repository import GObject, Nautilus


class CopyPathExtension(GObject.GObject, Nautilus.MenuProvider):
    def get_file_items(self, files):
        return self._items("CopyPathExtension::CopySelectionPath", files)

    def get_background_items(self, folder):
        return self._items("CopyPathExtension::CopyFolderPath", [folder])

    # Nautilus keys the menu action by item name, so the two menus need distinct ones or the last registered wins for both.
    def _items(self, name, files):
        paths = [f.get_location().get_path() for f in files]
        paths = [p for p in paths if p]
        if not paths:
            return []

        label = "Copy Path" if len(paths) == 1 else f"Copy {len(paths)} Paths"
        item = Nautilus.MenuItem(name=name, label=label)
        item.connect("activate", self._copy, paths)
        return [item]

    def _copy(self, menu_item, paths):
        subprocess.run(["wl-copy"], input="\n".join(paths).encode())
