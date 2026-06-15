pkgs:
{
  name = "preservation-firstboot-bind-mount";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../module.nix ];

      preservation = {
        enable = true;
        preserveAt."/persistent" = {
          files = [
            { file = "/etc/machine-id"; inInitrd = true; }
          ];
        };
      };

      # hack for now to populate /sysroot/persistent/etc/machine-id before bind mount
      boot.initrd.systemd.services.machine-id = {
        script = ''
          if [ ! -s /sysroot/persistent/etc/machine-id ]; then
            echo "uninitialized" > /sysroot/persistent/etc/machine-id
          fi
        '';
        before = [
          "sysroot-etc-machine\\x2did.mount"
          "initrd-preservation.target"
        ];
        after = [ "systemd-tmpfiles-setup-preservation.service" ];
        wantedBy = [ "initrd-preservation.target" ];
      };

      systemd.services.systemd-machine-id-commit.unitConfig.ConditionFirstBoot = true;

      # test-specific configuration below
      boot.initrd.systemd.enable = true;

      networking.useNetworkd = true;

      virtualisation = {
        memorySize = 2048;
        # separate block device for preserved state
        emptyDiskImages = [ 23 ];
        fileSystems."/persistent" = {
          device = "/dev/vdb";
          fsType = "ext4";
          neededForBoot = true;
          autoFormat = true;
        };
      };

    };

  testScript =
    { nodes, ... }:
    # python
    ''
      machine.start(allow_reboot=True)
      machine.wait_for_unit("default.target")

      with subtest("Initial boot meets ConditionFirstBoot"):
        machine.require_unit_state("first-boot-complete.target","active")

      with subtest("Machine ID populated"):
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
