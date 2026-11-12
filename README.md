# Laptop Pet

A little desktop pet for Windows (PowerShell + WinForms). Cats, dogs, rabbits and fish walk around the screen,
eat from the feeder, sleep in the bed, play with a ball, and can chat with a friend's pet.

- Run: double-click `start_pet.vbs`, or build `dist\LaptopPet.exe` with `build_exe.ps1`.
- Updates: `publish_update.ps1` signs `pet.ps1` into `update/`. Installed copies check `update/latest.json`
  and only install a version whose signature matches the public key inside `pet.ps1`.