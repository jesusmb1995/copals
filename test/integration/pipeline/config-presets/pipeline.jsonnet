local r = import 'lib/repos.libsonnet';

{
  Description: 'Pipeline integration test — exercises multiple install operations and screenshot',
  base_image: 'docker.io/library/debian:testing',
  repositories: [
    r.pkg_install + { enabled: true },
    r.file_ops + { enabled: true },
    r.sh_tasks + { enabled: true },
  ],
}
