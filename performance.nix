# Performance and system tuning for AMD Ryzen 3 3300X, NVIDIA GTX 1660 SUPER, ZRAM, and BORE
{ config, pkgs, lib, ... }:

{
  # 1. Параметры ядра для процессора AMD Zen 2 (Ryzen 3 3300X)
  boot.kernelParams = [
    "amd_pstate=active"
    "split_lock_detect=off"
  ];

  # TCP BBR + FQ сетевой стек
  boot.kernelModules = [ "tcp_bbr" ];

  boot.kernel.sysctl = {
    # Минимальный сетевой пинг и справедливая очередь пакетов
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";

    # Тюнинг планировщика CachyOS BORE (Burst-Oriented Response Enhancer)
    "-kernel.sched_bore" = lib.mkDefault 1;
    "-kernel.sched_burst_cache_lifetime" = lib.mkDefault 75000000;
    "-kernel.sched_burst_penalty_scale" = lib.mkDefault 1536;
    "-kernel.sched_burst_smoothness" = lib.mkDefault 1;
    "kernel.sched_cfs_bandwidth_slice_us" = lib.mkDefault 3000;
    "-kernel.sched_migration_cost_ns" = lib.mkDefault 500000;

    # Виртуальная память (оптимизировано под быстрый ZRAM со сжатием zstd)
    "vm.swappiness" = lib.mkDefault 180;
    "vm.watermark_boost_factor" = lib.mkDefault 0;
    "vm.watermark_scale_factor" = lib.mkDefault 125;
    "vm.page-cluster" = lib.mkDefault 0;
    "vm.vfs_cache_pressure" = lib.mkDefault 50;
    "vm.dirty_background_ratio" = lib.mkDefault 5;
    "vm.dirty_ratio" = lib.mkDefault 10;
  };

  # 2. Быстрое сжатие оперативной памяти ZRAM (алгоритм zstd)
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
    priority = 100;
  };

  # 3. Интеллектуальный демон приоритизации процессов Ananicy-cpp
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;

    extraTypes = [
      {
        type = "Compiler";
        nice = 19;
        ioclass = "idle";
        sched = "batch";
      }
    ];

    extraRules = [
      { name = "rustc"; type = "Compiler"; }
      { name = "cargo"; type = "Compiler"; }
      { name = "gcc"; type = "Compiler"; }
      { name = "g++"; type = "Compiler"; }
      { name = "clang"; type = "Compiler"; }
      { name = "niri"; type = "LowLatency_RT"; }
      { name = "pipewire"; type = "LowLatency_RT"; }
      { name = "wireplumber"; type = "LowLatency_RT"; }
      { name = "prismlauncher"; type = "Launcher"; }
      { name = "wine64-preloader"; type = "Game"; }
    ];
  };

  # 4. Сохранение VRAM видеокарты NVIDIA при сне/гибернации
  hardware.nvidia.powerManagement.enable = lib.mkForce true;

  # Права GameMode для пользователя spike
  users.users."spike".extraGroups = [ "gamemode" ];

  # Настройки GameMode (автоматический разгон PowerMizer и приоритет в играх)
  programs.gamemode = {
    enable = true;
    enableRenice = true;
    settings = {
      general = {
        desiredgov = "performance";
        defaultgov = "powersave";
        renice = 10;
        ioprio = 0;
        disable_splitlock = 1;
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        nv_powermizer_mode = 1;
      };
    };
  };

  # 5. Планировщики ввода-вывода (NVMe: kyber, SATA SSD/HDD: bfq)
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="kyber"
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="bfq"
  '';
}
