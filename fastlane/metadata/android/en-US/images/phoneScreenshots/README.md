# screenshots

izzyondroid and f-droid list an app with the screenshots found here, named
`1.png`, `2.png`, ... in display order. they are still missing; capture them
from a release build on a device or emulator:

```
adb exec-out screencap -p > fastlane/metadata/android/en-US/images/phoneScreenshots/1.png
```

worth showing: the listing with a few lists, an open list with items in several
states, the state picker, and the share dialog with its qr code. use throwaway
list names - a screenshot published to a store is public forever.
