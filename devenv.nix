{ pkgs, lib, config, inputs, ... }:

{
  dotenv.enable = true;

  languages.javascript = {
    enable = true;
    pnpm.enable = true;
  };
  languages.python.enable = true;
  languages.python.version = "3.13";
  languages.python.uv.enable = true;
  languages.python.venv.enable = true;
  languages.python.venv.requirements = ./requirements.txt;
  enterShell = ''
    # Auto-activate devenv-managed virtualenv when entering the shell
    if [ -f .devenv/state/venv/bin/activate ]; then
      # Works for bash, zsh, etc.
      . .devenv/state/venv/bin/activate
    fi
  '';
  packages = with pkgs; [
    tcpdump
    cargo
    nil
    nixd
    arp-scan
    gh
    nmap
    bettercap
  ];

  scripts.network-scan.exec = ''
    exec "$DEVENV_ROOT/network_security/network_scan.sh" "$@"
  '';

  scripts.pin-intruder.exec = ''
    exec "$DEVENV_ROOT/network_security/pin_intruder.sh" "$@"
  '';

  scripts.sentinel.exec = ''
    exec "$DEVENV_ROOT/sentinel.sh" "$@"
  '';

  scripts.investigate.exec = ''
    exec "$DEVENV_ROOT/investigate.sh" "$@"
  '';

}
