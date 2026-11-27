# Единый файл настроек для адаптации Spike-dotfiles под ваш ПК.
# Измените значения ниже и скопируйте свой /etc/nixos/hardware-configuration.nix в корень репозитория.
{
  username = "spike";
  userDescription = "Spike";
  hostName = "nixos";

  # Видеокарта: "nvidia" | "amd" | "intel" | "vm"
  gpu = "nvidia";

  # true — если корень на LUKS с именем "cryptroot" (разрешает TRIM/discard)
  luksCryptroot = false;

  # true — если корень на Btrfs (включает ежемесячный btrfs scrub)
  btrfsScrub = false;

  timeZone = "Europe/Moscow";
  locale = "ru_RU.UTF-8";

  gitName = "Spike";
  gitEmail = "spike@nixos.local";
}
