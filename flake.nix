{
  description = "A flake for running a configured Unbound DNS resolver on non-NixOS systems";

  inputs = {
    # Используем стабильный канал nixpkgs, но можно и unstable
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or a specific release
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # --- НОВЫЙ БЛОК: СКАЧИВАЕМ ROOT.HINTS ---
      # Мы явно скачиваем файл с корневыми DNS-серверами.
      # SHA256-хэш гарантирует, что файл не будет подменен.
      rootHintsFile = pkgs.fetchurl {
        url = "https://www.internic.net/domain/named.root";
        sha256 = "";
      };

      unboundConf = pkgs.writeText "unbound.conf" ''
        server:
          pidfile: ""
          chroot: ""
          directory: ""

          use-syslog: no
          logfile: ""
          verbosity: 3

          # --- ИЗМЕНЕНИЕ: УКАЗЫВАЕМ ПРАВИЛЬНЫЙ ПУТЬ ---
          # Ссылаемся на скачанный нами файл в /nix/store
          root-hints: "${rootHintsFile}"

          interface: 127.0.0.1
          port: 5353
          access-control: 127.0.0.1/32 allow

          msg-cache-size: 64m
          rrset-cache-size: 128m

          harden-glue: yes
          harden-dnssec-stripped: yes
          use-caps-for-id: yes
          qname-minimisation: yes
          private-address: 192.168.0.0/16
          private-address: 172.16.0.0/12
          private-address: 10.0.0.0/8

          # Используем DNS-over-HTTPS (DoH)
          forward-zone:
            name: "."
            forward-ssl-upstream: yes
            forward-addr: 1.1.1.1#cloudflare-dns.com/dns-query
            forward-addr: 1.0.0.1#cloudflare-dns.com/dns-query
            forward-addr: 8.8.8.8#dns.google/dns-query
            forward-addr: 8.8.4.4#dns.google/dns-query
      '';

      unbound-runner = pkgs.writeShellScriptBin "unbound-start" ''
        #!${pkgs.stdenv.shell}
        echo "Starting Unbound with config: ${unboundConf}"
        echo "Listening on 127.0.0.1:5353..."
        exec ${pkgs.unbound}/bin/unbound -d -c ${unboundConf}
      '';

    in {
      # ... остальная часть файла без изменений ...
      packages.${system}.default = unbound-runner;
      apps.${system}.default = {
        type = "app";
        program = "${unbound-runner}/bin/unbound-start";
      };
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          unbound-runner
          pkgs.unbound
          pkgs.dnsutils
        ];
      };
    };
}