{ pkgs, home-manager }:
{
  name = "preservation-home-manager";

  nodes.machine =
    { ... }:
    {
      imports = [
        ../module.nix
        home-manager.nixosModules.home-manager
      ];

      preservation.enable = true;

      users.users.alice = {
        isNormalUser = true;
        # custom home directory
        home = "/home/wonderland";
      };

      # alice's preservation is declared through Home Manager only
      home-manager.users.alice =
        { config, ... }:
        {
          home.stateVersion = "25.05";

          preservation.preserveAt."/state" = {
            directories = [
              # relative to the home directory
              ".rabbit_hole"
            ];
            files = [
              # absolute below the home directory
              {
                file = "${config.xdg.configHome}/foo";
                mode = "0600";
              }
            ];
          };
        };

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
    let
      home = nodes.machine.users.users.alice.home;
    in
    # (for syntax highlighting)
    /* python */ ''
      machine.start(allow_reboot=True)
      machine.wait_for_unit("default.target")

      with subtest("Home Manager preservation is mounted"):
        machine.succeed("mountpoint ${home}/.rabbit_hole")
        machine.succeed("mountpoint ${home}/.config/foo")

      with subtest("Type, permissions and ownership"):
        actual = machine.succeed("stat -c '0%a %U %G' ${home}/.rabbit_hole | tee /dev/stderr").strip()
        t.assertEqual(actual, "0755 alice users", "unexpected file attributes")
        actual = machine.succeed("stat -c '0%a %U %G' ${home}/.config/foo | tee /dev/stderr").strip()
        t.assertEqual(actual, "0600 alice users", "unexpected file attributes")

      with subtest("State lands on the persistent prefix"):
        machine.succeed("echo -n foobarbaz > ${home}/.config/foo")
        content = machine.succeed("cat /state${home}/.config/foo")
        t.assertEqual(content, "foobarbaz", "unexpected file content")

      machine.shutdown()
    '';
}
