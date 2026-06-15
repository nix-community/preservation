pkgs:
let
  inherit (pkgs) lib;
  preservationLib = import ../lib.nix { inherit lib; };
in
{
  name = "preservation-basic";

  nodes.machine =
    { pkgs, ... }:
    {
      # import the preservation module
      imports = [ ../module.nix ];

      # module configuration
      preservation = {
        # global enable switch
        enable = true;
        # all files and directories are preserved under "/state" in this test
        preserveAt."/state" = {
          commonMountOptions = [
            "x-foo"
          ];
          directories = [
            "/var/lib/someservice"
            "/var/log"
          ];
          files = [
            { file = "/etc/wpa_supplicant.conf"; how = "symlink"; }
            # some files need to be prepared very early, machine-id is one such case
            { file = "/etc/machine-id"; inInitrd = true; }
            # persist SSH host keys
            { file = "/etc/ssh/ssh_host_rsa_key"; how = "symlink"; configureParent = true; }
            { file = "/etc/ssh/ssh_host_ed25519_key"; how = "symlink"; configureParent = true; }
          ];
          # per-user configuration is possible
          # similar to impermanence this configures ownership for the respective users
          users = {
            alice = {
              directories = [
                ".rabbit_hole"
              ];
            };
            butz = {
              commonMountOptions = [
                "x-bar"
              ];
              files = [
                { file = ".config/foo"; mode = "0600"; }
                "bar"
                # an empty file with may be created at the symlink's
                # target, i.e. on the persistent volume
                { file = ".symlinks/baz"; how = "symlink"; createLinkTarget = true; }
                # this file should be mounted and with the combination of all three
                # configured `x-foo`, `x-bar` and `x-baz`.
                { file = "yay_userspace_mount_options"; mountOptions = [ "x-baz" ]; }
                # a symlinked file in the user's home directory
                { file = ".toplevel_symlink"; how = "symlink"; }
              ];
              directories = [
                "unshaved_yaks"
                "foo/bar/baz"
                { directory = "symlinked_user_dir"; how = "symlink"; }
              ];
            };
          };
        };
      };

      # systemd-machine-id-commit.service would fail, but it is not relevant
      # in this specific setup for a persistent machine-id so we disable it
      systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

      # to test sshd with preserved host keys
      services.openssh.enable = true;

      # test-specific configuration below

      testing.initrdBackdoor = true;
      boot.initrd.systemd = {
        enable = true;
        extraBin = {
          mountpoint = "${pkgs.util-linux}/bin/mountpoint";
        };
      };
      networking.useNetworkd = true;

      users.users = {
        alice = {
          isNormalUser = true;
          # custom home directory
          home = "/home/wonderland";
        };
        butz.isNormalUser = true;
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
      butzHome = nodes.machine.users.users.butz.home;

      allFiles = lib.flatten (
        lib.mapAttrsToList (_: preservationLib.getAllFiles) nodes.machine.preservation.preserveAt
      );
      allDirs = lib.flatten (
        lib.mapAttrsToList (_: preservationLib.getAllDirectories) nodes.machine.preservation.preserveAt
      );
      initrdFiles = builtins.filter (conf: conf.inInitrd) allFiles;
      initrdDirs = builtins.filter (conf: conf.inInitrd) allDirs;
      initrdJSON = builtins.toJSON (initrdDirs ++ initrdFiles);
      allJSON = builtins.toJSON (allDirs ++ allFiles);
    in
    # (for syntax highlighting)
    /* python */
    ''
      import json
      import os

      initrd_files = json.loads('${initrdJSON}')
      all_files = json.loads('${allJSON}')

      def check_file(config, in_initrd=False):
        prefix = "/sysroot" if in_initrd else ""
        file_path = config.get("directory", config.get("file"))
        path = f"{prefix}{file_path}"

        match config["how"]:
          case "bindmount":
            # check that file is mounted
            machine.succeed(f"mountpoint {path}")

            # check permissions and ownership
            actual = machine.succeed(f"stat -c '0%a %U %G' {path} | tee /dev/stderr").strip()
            expected = "{} {} {}".format(config["mode"],config["user"],config["group"])
            t.assertEqual(actual, expected, "unexpected file attributes")

          case "symlink":
            # check that file is _not_ mounted
            machine.fail(f"mountpoint {path}")

          case "_intermediate":
            # intermediate paths only ever refer to directories
            machine.succeed(f"test -d {path}")

            # check permissions and ownership
            actual = machine.succeed(f"stat -c '0%a %U %G' {path} | tee /dev/stderr").strip()
            expected = "{} {} {}".format("0755",config["user"],config["group"])
            t.assertEqual(actual, expected, "unexpected file attributes")

          case x:
            raise Exception(f"Unknown case: {x}")

        if config.get("configureParent") == True:
          parent = os.path.dirname(path)
          config = config["parent"]
          # check permissions and ownership of parent directory
          actual = machine.succeed(f"stat -c '0%a %U %G' {parent} | tee /dev/stderr").strip()
          expected = "{} {} {}".format(config["mode"],config["user"],config["group"])
          t.assertEqual(actual, expected, "unexpected file attributes")


      machine.start(allow_reboot=True)
      machine.wait_for_unit("default.target")

      with subtest("Empty machine ID files and bindmount prepared in initrd"):
        machine.succeed("test -f /sysroot/etc/machine-id")
        machine.succeed("test -f /sysroot/state/etc/machine-id")

        # files are expected to be empty at this point
        machine.fail("test -s /sysroot/etc/machine-id")
        machine.fail("test -s /sysroot/state/etc/machine-id")

        mounts = machine.succeed("mount")
        t.assertIn("/sysroot/etc/machine-id", mounts, "/sysroot/etc/machine-id not in mounts")

      with subtest("Type, permissions and ownership in first boot initrd"):
        for file in initrd_files:
          check_file(file, in_initrd=True)

      machine.switch_root()
      machine.wait_for_unit("default.target")

      with subtest("Machine ID file still mounted and now populated"):
        machine.succeed("mountpoint /etc/machine-id")
        machine.succeed("test -s /etc/machine-id")

      with subtest("Type, permissions and ownership after first boot completed"):
        for file in all_files:
          check_file(file)

      with subtest("SSH host keys created at the persistent prefix"):
        machine.succeed("test -s /state/etc/ssh/ssh_host_rsa_key")
        machine.succeed("test -s /state/etc/ssh/ssh_host_ed25519_key")

      with subtest("sshd service running"):
        machine.wait_for_unit("sshd.service")

      with subtest("Unpreserved intermediate user directories have correct permissions and ownership"):
          for path_segment in [ "foo", "foo/bar" ]:
            actual = machine.succeed(f"stat -c '0%a %U %G' /home/butz/{path_segment} | tee /dev/stderr").strip()
            expected = "0755 butz users"
            t.assertEqual(actual, expected, "unexpected file attributes")

      with subtest("Unpreserved user home has same permissions and ownership on persistent prefix as actual user home"):
          actual = machine.succeed("stat -c '0%a %U %G' /state/home/butz | tee /dev/stderr").strip()
          expected = machine.succeed("stat -c '0%a %U %G' /home/butz | tee /dev/stderr").strip()
          t.assertEqual(actual, expected, "unexpected file attributes")

      with subtest("Files preserved across reboots"):
        # write something in one of the preserved files
        teststring = "foobarbaz"
        machine.succeed(f"echo -n '{teststring}' > ${butzHome}/bar")

        # get current machine id
        machine_id = machine.succeed("cat /etc/machine-id")

        # reboot to initrd
        machine.reboot()
        machine.wait_for_unit("default.target")

        # preserved machine-id resides on /state
        machine.succeed("test -s /sysroot/state/etc/machine-id")
        initrd_machine_id = machine.succeed("cat /sysroot/state/etc/machine-id")
        t.assertEqual(initrd_machine_id, machine_id, "machine id changed")

        # check that machine-id is already mounted in initrd
        mounts = machine.succeed("mount")
        t.assertIn("/sysroot/etc/machine-id", mounts, "/sysroot/etc/machine-id not in mounts")

        # check type, permissions and ownership before switch root
        for file in initrd_files:
          check_file(file, in_initrd=True)

        # proceed with boot
        machine.switch_root()
        machine.wait_for_unit("default.target")

        # check that machine-id remains unchanged in stage-2 after reboot
        machine.succeed("test -s /etc/machine-id")
        new_machine_id = machine.succeed("cat /etc/machine-id")
        t.assertEqual(new_machine_id, machine_id, "machine id changed")

        # check that state in file was also preserved
        machine.succeed("test -s ${butzHome}/bar")
        content = machine.succeed("cat ${butzHome}/bar")
        t.assertEqual(content, teststring, "unexpected file content")

      with subtest("Type, permissions and ownership after reboot"):
        for file in all_files:
          check_file(file)

      with subtest("Custom (userspace) mount options are applied"):
        utab_entry = machine.succeed("grep TARGET=/home/butz/yay_userspace_mount_options /run/mount/utab")
        for opt in [ "x-foo", "x-bar", "x-baz"]:
          t.assertIn(opt, utab_entry, "expected mount option not found")

      machine.shutdown()
    '';
}
