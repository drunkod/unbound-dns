{
  description = "A flake for running a configured Unbound DNS resolver on non-NixOS systems";

  inputs = {
    # Используем стабильный канал nixpkgs, но можно и unstable
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Or a specific release
  };

  outputs = { self, nixpkgs }:
    let
      # Мы ориентируемся на стандартную серверную архитектуру
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # --- Конфигурация Unbound ---
      # Вся конфигурация Unbound определяется здесь, в виде текста.
      # Это делает ее частью нашего пакета.
      unboundConf = pkgs.writeText "unbound.conf" ''
        server:

          # --- НОВЫЕ ИЗМЕНЕНИЯ ---
          # Отключаем использование стандартных системных путей,
          # которых нет в нашей Alpine + Nix среде.
          pidfile: ""      # Не создавать pid-файл
          chroot: ""       # Не делать chroot (смену корневой директории)
          directory: ""    # Не менять рабочую директорию
          # --- КОНЕЦ ИЗМЕНЕНИЙ ---

          # Для тестирования удобно выводить логи в консоль, а не в syslog
          use-syslog: no
          logfile: ""
          verbosity: 3

           # Добавляем путь к корневым серверам для надежности
          root-hints: "${pkgs.unbound}/etc/unbound/root.hints"         

          # Слушаем только на localhost.
          # Используем порт 5353 для тестов без sudo. Для продакшена поменяйте на 53.
          interface: 127.0.0.1
          port: 5353
          access-control: 127.0.0.1/32 allow

          # Включаем кеширование
          msg-cache-size: 64m
          rrset-cache-size: 128m

          # Настройки приватности и безопасности
          harden-glue: yes
          harden-dnssec-stripped: yes
          use-caps-for-id: yes
          qname-minimisation: yes
          private-address: 192.168.0.0/16
          private-address: 172.16.0.0/12
          private-address: 10.0.0.0/8

          # --- ИСПОЛЬЗУЕМ DNS-over-HTTPS (DoH) ---
          # Он работает через стандартный порт 443 и не блокируется провайдерами.
          forward-zone:
            name: "."
            forward-ssl-upstream: yes
            forward-addr: "https://1.1.1.1/dns-query"
            forward-addr: "https://1.0.0.1/dns-query"
            forward-addr: "https://dns.google/dns-query"
      '';

      # --- Создание нашего пакета ---
      # Мы создаем скрипт-обертку, который запускает unbound с нашей конфигурацией.
      unbound-runner = pkgs.writeShellScriptBin "unbound-start" ''
        #!${pkgs.stdenv.shell}
        echo "Starting Unbound with config: ${unboundConf}"
        echo "Listening on 127.0.0.1:5353..."
        # Флаг -d предотвращает демонизацию, чтобы unbound оставался в foreground
        # Флаг -c указывает путь к нашему файлу конфигурации
        exec ${pkgs.unbound}/bin/unbound -d -c ${unboundConf}
      '';

    in {
      # --- Выходные данные нашего флейка ---

      # Пакет, который можно собрать с помощью `nix build`
      packages.${system}.default = unbound-runner;

      # Приложение, которое можно запустить с помощью `nix run`
      # Это самый удобный способ для тестирования.
      apps.${system}.default = {
        type = "app";
        program = "${unbound-runner}/bin/unbound-start";
      };

      # Окружение для разработки, доступное через `nix develop`
      # Включает в себя наш скрипт и утилиты для тестирования.
      devShells.${system}.default = pkgs.mkShell {
        packages = [
          unbound-runner      # Наш скрипт для запуска
          pkgs.unbound        # Сам unbound для прямого доступа, если нужно
          pkgs.dnsutils       # Утилита `dig` для тестирования DNS
        ];
      };
    };
}