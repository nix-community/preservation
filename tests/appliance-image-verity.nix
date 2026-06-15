pkgs:
{
  name = "preservation-verity-image";

  nodes.machine =
    { config, lib, pkgs, modulesPath, ... }:
    let
      inherit (config.image.repart.verityStore) partitionIds;
    in
    {
      imports = [
        ../module.nix
        (modulesPath + "/image/repart.nix")
      ];

      preservation = {
        enable = true;
        preserveAt."/persistent" = {
          files = [
            {
              file = "/etc/machine-id";
              inInitrd = true;
              how = "symlink";
              configureParent = true;
              createLinkTarget = true;
            }
          ];
        };
      };

      boot.initrd.systemd.tmpfiles.settings.preservation."/sysroot/persistent/etc/machine-id".f = {
        argument = "uninitialized";
      };

      systemd.services.systemd-machine-id-commit = {
        unitConfig.ConditionPathIsMountPoint = [
          "" "/persistent/etc/machine-id"
        ];
        serviceConfig.ExecStart = [
          "" "systemd-machine-id-setup --commit --root /persistent"
        ];
      };

      system = {
        name = "preservation-verity";
        image = {
          id = config.system.name;
          version = "1";
        };
        activationScripts.usrbinenv = lib.mkForce "";
        etc.overlay.enable = true;
      };

      image.repart = {
        verityStore.enable = true;

        inherit (config.system) name;

        partitions =
         {
          ${partitionIds.esp} = {
            repartConfig = {
              Type = "esp";
              Format = "vfat";
              SizeMinBytes = if config.nixpkgs.hostPlatform.isx86_64 then "64M" else "96M";
            };
            contents =
              let
                inherit (config.nixpkgs.hostPlatform) efiArch;
                systemdBoot = "${pkgs.systemd}/lib/systemd/boot/efi/systemd-boot${efiArch}.efi";
              in
              {
              "/EFI/systemd/systemd-boot${efiArch}.efi".source = systemdBoot;
              "/EFI/BOOT/BOOT${lib.toUpper efiArch}.EFI".source = systemdBoot;
            };
          };
          ${partitionIds.store-verity}.repartConfig = {
            Minimize = "best";
          };
          ${partitionIds.store}.repartConfig = {
            Minimize = "best";
          };
        };
      };

      boot.initrd.systemd.enable = true;

      networking.useNetworkd = true;

      services.userborn = {
        enable = true;
        passwordFilesLocation = "/persistent/etc";
      };

      fileSystems = {
        "/" = {
          fsType = "tmpfs";
          options = [ "mode=0755" ];
        };
        "/persistent" = {
          device = "/dev/vdb";
          fsType = "ext4";
          neededForBoot = true;
          autoFormat = true;
        };
      };

      virtualisation = {
        memorySize = 2048;
        emptyDiskImages = [ 23 ];
        directBoot.enable = false;
        mountHostNixStore = false;
        useEFIBoot = true;
        fileSystems = lib.mkVMOverride { };
      };
    };

  testScript =
    { nodes, ... }:
    # python
    ''
      import os
      import subprocess
      import tempfile

      tmp_disk_image = tempfile.NamedTemporaryFile()

      subprocess.run([
        "${nodes.machine.virtualisation.qemu.package}/bin/qemu-img",
        "create",
        "-f",
        "qcow2",
        "-b",
        "${nodes.machine.system.build.image}/${nodes.machine.image.fileName}",
        "-F",
        "raw",
        tmp_disk_image.name,
      ])

      os.environ['NIX_DISK_IMAGE'] = tmp_disk_image.name

      machine.start(allow_reboot=True)
      machine.wait_for_unit("default.target")

      with subtest("Running with volatile root"):
        machine.succeed("findmnt --kernel --type tmpfs /")

      with subtest("/nix/store is backed by dm-verity protected fs"):
        verity_info = machine.succeed("dmsetup info --target verity usr")
        t.assertIn("ACTIVE", verity_info, "unexpected verity info")

        backing_device = machine.succeed("df --output=source /nix/store | tail -n1").strip()
        t.assertEqual("/dev/mapper/usr", backing_device, "unexpected backing device")

      with subtest("Initial boot meets ConditionFirstBoot"):
        machine.require_unit_state("first-boot-complete.target","active")

      with subtest("Machine ID linked and populated"):
        machine.succeed("test -L /etc/machine-id")
        machine.succeed("test -s /persistent/etc/machine-id")
        machine_id = machine.succeed("cat /etc/machine-id")
        t.assertNotEqual("uninitialized", machine_id, "machine id not populated")

      with subtest("Machine ID persisted"):
        first_id = machine.succeed("cat /etc/machine-id")
        machine.reboot()
        machine.wait_for_unit("default.target")
        second_id = machine.succeed("cat /etc/machine-id")
        t.assertEqual(first_id, second_id, "machine-id changed")

      with subtest("Second boot does not meet ConditionFirstBoot"):
        machine.require_unit_state("first-boot-complete.target", "inactive")

      machine.shutdown()
    '';
}
