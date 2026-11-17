import settings


class WoWForeverSettings(settings.Group):
    class WoWPath(settings.OptionalUserFolderPath):
        """
        The World of Warcraft: Forever game folder, the one that contains the 'Interface' and 'WTF' folders.
        The client reads WTF/Account/*/SavedVariables/WoWForeverAP.lua and writes only
        Interface/AddOns/WoWForeverAP_Inbox/Inbox.lua inside it.
        """
        description = "World of Warcraft: Forever game folder"

    wow_path: WoWPath = WoWPath("")
