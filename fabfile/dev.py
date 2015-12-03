"""
Copyright 2015 iNuron NV

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

from env import *
import alba
from fabric.api import local, task, warn_only
import time
from uuid import uuid4
import sha
import json
import hashlib

@task
def check():
    where = local
    where("test -f %s" % env['alba_bin'])
    where("test -f %s" % env['arakoon_bin'])

@task
def compile():
    where = local
    where("cd cpp/ && tup")
    where("make")

@task
def clean():
    where = local
    with warn_only():
        where("rm -f cpp/bin/*.out")
        where("rm -f cpp/src/caas/*.o")
        where("rm -f cpp/src/examples/*.o")
        where("rm -f cpp/src/lib/*.o")
        where("rm -f cpp/src/tests/*.o")
        where("cd ocaml/ && rm -rf _build")


def setup_demo_alba(kind = default_kind):
    alba.demo_kill()
    alba.demo_setup()

@task
def run_tests_cpp(xml=False, kind=default_kind,
                  valgrind = False,
                  filter = None):

    setup_demo_alba(kind)

    where = local
    where("rm -rf %s/ocaml/" % ALBA_BASE_PATH)
    cmd = "./cpp/bin/unit_tests.out"
    if xml:
        cmd = cmd + " --gtest_output=xml:gtestresults.xml"
    if valgrind:
        cmd = "valgrind " + cmd
    if filter:
        cmd = cmd + " --gtest_filter=%s" % filter
    where(cmd)

@task
def run_tests_ocaml(xml=False, kind = default_kind, dump = None, filter = None):
    alba.demo_kill()
    alba.arakoon_start()
    alba.wait_for_master()

    alba.maintenance_start()
    alba.proxy_start()
    alba.nsm_host_register_default()

    alba.start_osds(kind, N, False)

    alba.claim_local_osds(N)

    where = local
    where("rm -rf %s/ocaml/" % ALBA_BASE_PATH)

    cmd = "./ocaml/alba.native unit-tests"
    if xml:
        cmd = cmd + " --xml=true"
    if filter:
        cmd = cmd + " --only-test=%s" % filter
    if dump:
        cmd = cmd + " > %s" % dump

    where(cmd)


@task
def run_tests_voldrv_backend(xml=False, kind = default_kind,
                             filter = None, dump = None):
    alba.demo_kill()
    alba.demo_setup(kind)
    time.sleep(1)
    where = local
    cmd0 = ""
    #cmd0 = "valgrind -v --track-origins=yes --leak-check=full --leak-resolution=high "
    cmd = cmd0 + "%s --skip-backend-setup 1 --backend-config-file ./cfg/backend.json" % env['voldrv_backend_test']
    if filter:
        cmd = cmd + " --gtest_filter=%s" % filter
    if xml:
        cmd = cmd + " --gtest_output=xml:gtestresults.xml"
    if dump:
        cmd = cmd + " > %s 2>&1" % dump
    where(cmd)

@task
def run_tests_voldrv_tests(xml=False, kind = default_kind, dump = None):
    alba.demo_kill()
    alba.demo_setup(kind)
    time.sleep(1)
    where = local
    cmd = "%s --skip-backend-setup 1 --backend-config-file ./cfg/backend.json --gtest_filter=SimpleVolumeTests/SimpleVolumeTest* --loglevel=error" % env['voldrv_tests']
    if xml:
        cmd = cmd + " --gtest_output=xml:gtestresults.xml"
    if dump:
        cmd = cmd + " 2> %s" % dump # in this case, we need sterr
    where(cmd)

@task
def run_tests_disk_failures(xml=False):
    alba.demo_kill()
    alba.demo_setup()
    time.sleep(1)
    where = local
    cmd = "%s" % env['failure_tester']
    if xml:
        cmd = cmd + " --xml=true"
    where(cmd)

@task
def run_tests_stress(kind = default_kind, xml = False):
    alba.demo_kill()
    alba.demo_setup(kind)
    time.sleep(1)
    where = local
    #
    n = 3000
    def build_cmd(command):
        cmd = [
        env['alba_bin'],
            command
        ]
        return cmd

    def create_namespace_cmd(name):
        cmd = build_cmd('proxy-create-namespace')
        cmd.append(name)
        cmd_s = ' '.join(cmd)
        return cmd_s

    def list_namespaces_cmd():
        cmd = build_cmd('list-namespaces')
        cmd.append('--to-json')
        cmd.append('2> /dev/null')
        cmd_s = ' '.join(cmd)
        return cmd_s

    template = "%20i"

    for i in xrange(n):
        name = template % i
        cmd_s = create_namespace_cmd(name)
        where (cmd_s)
    # they exist?
    v = where(list_namespaces_cmd(),
              capture = True)
    parsed = json.loads(v)
    print parsed
    assert parsed["success"] == True
    ns = parsed["result"]
    print len(ns)
    assert (len(ns) == n+1)

    if xml:
        alba.dump_junit_xml()

@task
def run_tests_recovery(xml = False):
    alba.demo_kill()

    # set up separate albamgr & nsm host
    abm_cfg = "cfg/test_abm.ini"
    nsm_cfg = "cfg/test_nsm_1.ini"
    alba.arakoon_start_(abm_cfg, "%s/abm_0" % ALBA_BASE_PATH, ["micky_0"])
    alba.arakoon_start_(nsm_cfg, "%s/nsm_1" % ALBA_BASE_PATH, ["zicky_0"])

    alba.wait_for_master(abm_cfg)
    alba.wait_for_master(nsm_cfg)

    alba.nsm_host_register(nsm_cfg, albamgr_cfg = abm_cfg)

    alba.maintenance_start(abm_cfg = abm_cfg)
    alba.proxy_start(abm_cfg = abm_cfg)

    N = 3
    alba.start_osds("ASD", N, False)

    alba.claim_local_osds(N, abm_cfg = abm_cfg)

    alba.maintenance_stop()

    ns = 'test'
    alba.create_namespace(ns, abm_cfg = abm_cfg)

    obj_name = 'alba_binary'
    cmd = [
        env['alba_bin'],
        'upload-object', ns, env['alba_bin'], obj_name,
        '--config', abm_cfg
    ]
    local(' '.join(cmd))

    cmd = [
        env['alba_bin'],
        'show-object', ns, obj_name,
        '--config', abm_cfg
    ]
    local(' '.join(cmd))

    checksum1 = local('md5sum %s' % env['alba_bin'], capture=True)

    # kill nsm host
    local('fuser -n tcp 4001 -k')
    local('rm -rf %s/nsm_1' % ALBA_BASE_PATH)

    cmd = [
        env['alba_bin'],
        'update-nsm-host',
        nsm_cfg,
        '--lost',
        '--config', abm_cfg
    ]
    local(' '.join(cmd))

    # start new nsm host + register it to albamgr
    alba.arakoon_start_("cfg/test_nsm_2.ini", "%s/nsm_2" % ALBA_BASE_PATH, ["ticky_0"])
    alba.wait_for_master("cfg/test_nsm_2.ini")
    cmd = [
        env['alba_bin'],
        "add-nsm-host",
        'cfg/test_nsm_2.ini',
        "--config",
        abm_cfg
    ]
    local(' '.join(cmd))

    # recover namespace to the new nsm host
    cmd = [
        env['alba_bin'],
        'recover-namespace', ns, 'ticky',
        '--config', abm_cfg
    ]
    local(' '.join(cmd))

    cmd = [
        env['alba_bin'],
        'deliver-messages',
        '--config', abm_cfg
    ]
    local(' '.join(cmd))
    local(' '.join(cmd))

    # bring down one of the osds
    # we should be able to handle this...
    alba.osd_stop(8000)

    local('mkdir -p %s/recovery_agent' % ALBA_BASE_PATH)
    cmd = [
        env['alba_bin'],
        'namespace-recovery-agent',
        ns, '%s/recovery_agent' % ALBA_BASE_PATH, '1', '0',
        "--config", abm_cfg,
        "--osd-id 1 --osd-id 2"
    ]
    local(' '.join(cmd))

    dfile = 'destination_file.out'
    local('rm -f %s' % dfile)
    cmd = [
        env['alba_bin'],
        'download-object', ns, obj_name, dfile,
        "--config", abm_cfg
    ]
    local(' '.join(cmd))

    checksum1 = hashlib.md5(open(env['alba_bin'], 'rb').read()).hexdigest()
    checksum2 = hashlib.md5(open(dfile, 'rb').read()).hexdigest()

    print "Got checksums %s & %s" % (checksum1, checksum2)

    assert (checksum1 == checksum2)

    # TODO 1
    # iets asserten ivm hoeveel fragments er in manifest aanwezig zijn
    # dan osd 0 starten en recovery opnieuw draaien
    # die moet kunnen de extra fragments goed benutten

    # TODO 2
    # object eerst es overschrijven, dan recovery doen
    # en zien of we laatste versie krijgen

    # TODO 3
    # add more objects (and verify them all)

    # TODO 4
    # start met 1 osd die alive is

    if xml:
        alba.dump_junit_xml()


@task
def spreadsheet_my_ass(start=0, end = 13400):
    env['osds_on_separate_fs'] = True
    start = int(start)
    def fresh():
        alba.demo_kill()
        alba.demo_setup()

        # deliver osd & nsm messages
        time.sleep(1)
        cmd = [
            env['alba_bin'],
            'deliver-messages',
            '--config', arakoon_config_file
        ]
        local(' '.join(cmd))

        # stop asd 0
        alba.osd_stop(8000)

    if start == 0:
        fresh()

    # fill the demo namespace
    local("dd if=/dev/urandom of=%s/obj bs=40K count=1" % ALBA_BASE_PATH)
    for i in xrange(start, end):
        cmd = [
            env['alba_bin'],
            'proxy-upload-object',
            'demo', '%s/obj' % ALBA_BASE_PATH,
            str(i)
        ]
        local(" ".join(cmd))

    # show the disk usage
    local("df")

    # restart asd 0 as a not slow asd
    alba._detach(
        [ env['alba_bin'], 'asd-start', '--config', '%s/asd/00/cfg.json' % ALBA_BASE_PATH ],
        out='%s/asd/00/output' % ALBA_BASE_PATH
    )

    # let maintenance process do some rebalancing
    time.sleep(120)
    local("df")


@task
def run_test_asd_start(xml=False):
    alba.demo_kill()
    alba.demo_setup()

    object_location = "%s/obj" % ALBA_BASE_PATH
    local("dd if=/dev/urandom of=%s bs=1M count=1" % object_location)

    for i in xrange(0, 1000):
        cmd = [
            env['alba_bin'],
            'proxy-upload-object',
            'demo', object_location,
            str(i)
        ]
        local(" ".join(cmd))

    for i in xrange(0, N):
        alba.osd_stop(8000 + i)

    alba.start_osds(default_kind, N, True)
    time.sleep(2)

    cmd = [
        env['alba_bin'],
        'proxy-upload-object',
        'demo', object_location,
        "fdskii", "--allow-overwrite"
    ]
    with warn_only():
        # this clears the borked connections from the
        # asd connection pools
        local(" ".join(cmd))
        local(" ".join(cmd))
        local(" ".join(cmd))
        time.sleep(2)
        local(" ".join(cmd))

    local(" ".join(cmd))

    local(" ".join([
        env['alba_bin'],
        'proxy-download-object',
        'demo', '1', '%s/obj2' % ALBA_BASE_PATH
    ]))

    alba.smoke_test()

    if xml:
        alba.dump_junit_xml()

@task
def run_test_big_object():
    alba.demo_kill()
    alba.demo_setup()

    # create the preset in albamgr
    local(" ".join([
        env['alba_bin'],
        'create-preset', 'preset_no_compression',
        '--config', arakoon_config_file,
        '< ./cfg/preset_no_compression.json'
    ]))

    # create new namespace with this preset
    local(" ".join([
        env['alba_bin'],
        'create-namespace', 'big', 'preset_no_compression',
        '--config', arakoon_config_file
    ]))

    object_file = "%s/obj" % ALBA_BASE_PATH
    # upload a big object
    local("truncate -s 2G %s" % object_file)
    local(" ".join([
        'time', env['alba_bin'],
        'proxy-upload-object', 'big', object_file, 'bigobj'
    ]))
    # note this may fail with NoSatisfiablePolicy from time to time

    local(" ".join([
        'time', env['alba_bin'],
        'proxy-download-object', 'big', 'bigobj', '%s/obj_download' % ALBA_BASE_PATH
    ]))
    local("rm %s/obj_download" % ALBA_BASE_PATH)

    # policy says we can lose a node,
    # so stop and decommission osd 0 to 3
    for i in range(0,4):
        port = 8000+i
        alba.osd_stop(port)
        long_id = "%i_%i_%s" % (port, 2000, alba.local_nodeid_prefix)
        local(" ".join([
            env['alba_bin'],
            'decommission-osd', '--long-id', long_id,
            '--config', arakoon_config_file
        ]))

    # TODO
    # wait for maintenance process to repair it
    # (give maintenance process a kick?)
    # report mem usage of proxy & maintenance process

@task
def run_test_arakoon_changes ():
    alba.demo_kill ()
    alba.demo_setup(arakoon_config_file = arakoon_config_file_2)
    # 2 node cluster, and arakoon_0 will be master.
    def stop_node(node_name):
        r = local("pgrep -a arakoon | grep '%s'" % node_name, capture = True)
        info = r.split()
        pid = info[0]
        local("kill %s" % pid)

    def start_node(node_name, cfg):
        inner = [
            env['arakoon_bin'],
            "--node", node_name,
            "-config", cfg
        ]
        cmd_line = alba._detach(inner)
        local(cmd_line)

    def signal_alba(process_name,signal):
        r = local("pgrep -a alba | grep %s" % process_name, capture = True)
        info = r.split()
        pid = info[0]
        local("kill -s %s %s" % (signal, pid))

    def wait_for(delay):
        n = int(delay)
        print "sleeping %i" % n
        while n:
            print "\t%i" % n
            time.sleep(1)
            n = n - 1

    # 2 node cluster, and arakoon_0 is master.
    wait_for(10)
    stop_node('arakoon_0')
    stop_node('witness_0')
    # restart them with other config

    start_node('arakoon_1', arakoon_config_file)
    start_node('witness_0', arakoon_config_file)

    wait_for(20)
    start_node('arakoon_0', arakoon_config_file)

    maintenance_home = "%s/maintenance" % ALBA_BASE_PATH
    maintenance_cfg = maintenance_home + "/albamgr.cfg"
    local("cp %s %s" % (arakoon_config_file, maintenance_cfg))
    signal_alba('maintenance','USR1')
    wait_for(120)
    cfg_s = local("%s proxy-client-cfg | grep port | wc" % env['alba_bin'], capture=True)
    c = cfg_s.split()[0]
    assert (c == '3') # 3 nodes in config
