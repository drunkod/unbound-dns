{
  description = "A flake for running a basic recursive Unbound DNS resolver";

  inputs = {
    # Используем стабильный канал nixpkgs, но можно и unstable
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or a specific release
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # cacert больше не нужен для этой конфигурации, но пусть останется
      cacert = pkgs.cacert; 

      rootHintsFile = pkgs.fetchurl {
        url = "https://www.internic.net/domain/named.root";
        sha256 = "sha256-H2loKjfXhWsc9XRl4IDlm1jQ0E67SgwjopMwxti3JWA=";
      };

      unboundConf = pkgs.writeText "unbound.conf" ''
        server:
          pidfile: ""
          chroot: ""
          directory: ""

          use-syslog: no
          logfile: ""
          verbosity: 3
          
          # Указываем Unbound, где найти корневые серверы.
          # Он будет работать как полноценный рекурсивный резолвер.
          root-hints: "${rootHintsFile}"

          interface: 127.0.0.1
          port: 5353
          access-control: 127.0.0.1/32 allow
          
          # Разрешаем запросы из любой приватной сети, если понадобится
          access-control: 10.0.0.0/8 allow
          access-control: 172.16.0.0/12 allow
          access-control: 192.168.0.0/16 allow

          # Мы убрали всю секцию forward-zone.
          # Unbound теперь не будет пересылать запросы, а будет разрешать их сам.
      '';

      unbound-runner = pkgs.writeShellScriptBin "unbound-start" ''
        #!${pkgs.stdenv.shell}
        echo "Starting Unbound as a recursive resolver..."
        echo "Listening on 127.0.0.1:5353..."
        exec ${pkgs.unbound}/bin/unbound -d -c ${unboundConf}
      '';

    in {
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