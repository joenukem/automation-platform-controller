#!/usr/bin/env python3
"""Render the upstream Dockerfile template headless, without ansible.

Upstream generates its Dockerfile via ansible-playbook; the only templating
actually used is jinja2 plus ansible's `bool` filter, so a 30-line renderer
replaces the whole toolchain (proven in Phase 0).
"""
import sys, os, jinja2

def main(awx_tree: str, receptor_image: str) -> None:
    tdir = os.path.join(awx_tree, 'tools/ansible/roles/dockerfile/templates')
    env = jinja2.Environment(loader=jinja2.FileSystemLoader(tdir), keep_trailing_newline=True)
    env.filters['bool'] = lambda v: bool(v) if not isinstance(v, str) else v.lower() in ('1', 'true', 'yes', 'y')
    vars = dict(build_dev=False, kube_dev=False, headless=True,
                template_dest='_build', receptor_image=receptor_image)
    os.makedirs(os.path.join(awx_tree, '_build'), exist_ok=True)
    for t in ('supervisor_web.conf', 'supervisor_task.conf', 'supervisor_rsyslog.conf'):
        with open(os.path.join(awx_tree, '_build', t), 'w') as f:
            f.write(env.get_template(t + '.j2').render(**vars))
    df = env.get_template('Dockerfile.j2').render(**vars)
    # buildah here has no ssh forwarding; the git requirements are all https.
    df = df.replace('RUN --mount=type=ssh cd /tmp && make requirements_awx',
                    'RUN cd /tmp && make requirements_awx')
    # CTL-002: when a base-image mirror is configured, rewrite the quay.io
    # base + receptor FROMs to the franken registry so a release build has no
    # quay.io dependency for container images. (pip/dnf mirroring is separate.)
    mirror = os.environ.get('MIRROR_BASE')
    if mirror:
        df = df.replace('quay.io/centos/centos:stream9', mirror + '/centos/centos:stream9')
        df = df.replace('quay.io/ansible/receptor:devel', mirror + '/ansible/receptor:devel')
    with open(os.path.join(awx_tree, 'Dockerfile'), 'w') as f:
        f.write(df)
    print(f'rendered Dockerfile ({len(df)} bytes) + supervisor configs')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else (os.environ.get('MIRROR_BASE','').rstrip('/') + '/ansible/receptor:devel' if os.environ.get('MIRROR_BASE') else 'quay.io/ansible/receptor:devel'))
