{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    colmena.url = "github:zhaofengli/colmena";
  };

  outputs = { self, nixpkgs, colmena, ... }: {

    lib = {
      mkProxy = addr: {
        proxyPass = addr;
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };

    nixosModules = {
      nginx = { config, pkgs, lib, ... }: {
        security.acme = {
          acceptTerms = true;
          defaults.email = "sahiti93@gmail.com";
        };
        services.nginx = {
          enable = true;
          virtualHosts.${config.networking.fqdn} = {
            forceSSL = true;
            enableACME = true;
            locations = {
              "/" = {
                extraConfig = ''
                  # Redis cache configuration
                  set $key $uri;

                  # Try Redis first
                  redis2_query get $key;
                  redis2_pass localhost:${
                    builtins.toString config.services.redis.port
                  };

                  # If cache miss, proxy to MinIO
                  error_page 404 = @origin;
                '';
              };

              "@origin" = {
                proxyPass = "http://localhost:9000"; # MinIO
                extraConfig = ''
                  # Cache successful responses in Redis
                  redis2_query set $key $upstream_response_body;
                  redis2_pass localhost:${
                    builtins.toString config.services.redis.port
                  };

                  # Add cache headers
                  add_header X-Cache-Status $upstream_cache_status;
                '';
              };
            };
          };
        };
        services.prometheus.exporters.nginx.enable = true;
        services.prometheus.scrapeConfigs = [{
          job_name = "nginx";
          static_configs = [{
            targets = [
              "${config.networking.fqdn}:${
                builtins.toString
                config.services.prometheus.exporters.nginx.port
              }"
            ];
          }];
        }];
      };

      redis = { config, pkgs, lib, ... }: {
        services.redis.enable = true;
        services.prometheus.exporters.redis.enable = true;
        services.prometheus.scrapeConfigs = [{
          job_name = "redis";
          static_configs = [{
            targets = [
              "${config.networking.fqdn}:${
                builtins.toString
                config.services.prometheus.exporters.redis.port
              }"
            ];
          }];
        }];
      };

      minio = { config, pkgs, lib, ... }: {
        services.minio = {
          enable = true;
          browser = true;
        };
        services.prometheus.scrapeConfigs = [{
          job_name = "minio-job";
          bearer_token = "TOKEN";
          metrics_path = "/minio/v2/metrics/cluster";
          scheme = "https";
          static_configs = [{ targets = [ config.networking.fqdn ]; }];
        }];
      };
      monitoring = { config, pkgs, lib, ... }: {
        services.prometheus.enable = true;
        services.grafana = {
          enable = true;
          settings = {
            server = {
              http_addr = "127.0.0.1";
              # and Port
              http_port = 3000;
              domain = config.networking.fqdn;
              root_url =
                "https://${config.networking.fqdn}/grafana/"; # Not needed if it is `https://your.domain/`
              serve_from_sub_path = true;
            };
          };
        };
        services.nginx.virtualHosts."${config.networking.fqdn}" = {
          locations."/grafana/" = self.lib.mkProxy "http://${
              toString config.services.grafana.settings.server.http_addr
            }:${toString config.services.grafana.settings.server.http_port}";
        };
      };
    };

    colmenaHive = colmena.lib.makeHive {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [ ];
        };
      };

      catpix = { name, nodes, ... }: {
        deployment = {
          targetHost = "34.29.30.70";
          targetUser = "itihas";
        };
        nix.settings.trusted-users =  [ "itihas" ];
        networking.fqdn = "catpix.itihas.xyz";
        imports = with self.nixosModules; [
          "${nixpkgs}/nixos/modules/virtualisation/google-compute-image.nix"
          nginx
          redis
          minio
          monitoring
        ];
      };
    };
  };
}
