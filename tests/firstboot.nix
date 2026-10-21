pkgs:
{
  name = "preservation-firstboot";

  nodes.machine =
    { pkgs, ... }:
    {
      imports = [ ../module.nix ];

      preservation = {
        enable = true;
        preserveAt."/state" = {
          files = [
            { file = "/etc/machine-id"; inInitrd = true; how = "symlink"; configureParent = true; }
          ];
        };
      };

      systemd.services.systemd-machine-id-commit = {
        unitConfig.ConditionPathIsMountPoint = [
          "" "/state/etc/machine-id"
        ];
        serviceConfig.ExecStart = [
          "" "systemd-machine-id-setup --commit --root /state"
        ];
      };

      networking.useNetworkd = true;

      virtualisation = {
        memorySize = 2048;
        # separate block device for preserved state
        emptyDiskImages = [ 23 ];
        fileSystems."/state" = {
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

      with subtest("Machine ID linked and populated"):
        machine.succeed("test -L /etc/machine-id")
        machine.succeed("test -s /state/etc/machine-id")

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
