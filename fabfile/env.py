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

import os

cwd = os.getcwd()

def env_or_default(key, default):
    if os.environ.has_key(key):
        return os.environ[key]
    else:
        return default

def is_true(tls):
    return tls == 'True' or tls == 'true' or tls == True

ARAKOON_HOME = env_or_default("ARAKOON_HOME",
                              "%s/workspace/ARAKOON" % os.environ['HOME'])
ARAKOON_BIN = env_or_default("ARAKOON_BIN",
                         "%s/arakoon/arakoon.native" % ARAKOON_HOME)

VOLDRV_HOME = env_or_default("VOLDRV_HOME",
                             "%s/workspace/VOLDRV" % os.environ['HOME'])
VOLDRV_TEST = env_or_default("VOLDRV_TEST",
                             "%s/volumedriver_test" % VOLDRV_HOME)
VOLDRV_BACKEND_TEST = env_or_default("VOLDRV_BACKEND_TEST",
                                     "%s/backend_test" % VOLDRV_HOME)

ALBA_BIN = env_or_default("ALBA_BIN",
                          "%s/ocaml/alba.native" % cwd)

ALBA_PLUGIN_HOME = env_or_default("ALBA_PLUGIN_HOME",
                                  "%s/ocaml" % cwd)

ALBA_ASD_PATH_T = env_or_default("ALBA_ASD_PATH_T", "/tmp/alba/asd/%02i")

KINDS = ["ASD","KINETIC"]
env = {
    'alba_dev' : cwd,
    'alba_plugin_path' : ALBA_PLUGIN_HOME,
    'alba_bin' : ALBA_BIN,
    'kinetic_bin': '%s/bin/start_kinetic.sh' % cwd,
    'asd_path_t': ALBA_ASD_PATH_T,
    'arakoon_bin' : ARAKOON_BIN,
    'voldrv_backend_test' : VOLDRV_BACKEND_TEST,
    'voldrv_tests' : VOLDRV_TEST,
    'failure_tester' : "%s/ocaml/disk_failure_tests.native" % cwd,
    'osds_on_separate_fs' : False,
    'alba_tls' : env_or_default('ALBA_TLS', 'False'),
    'alba.0.6' : env_or_default('ALBA_06', 'alba.0.6')
}

arakoon_nodes = ["arakoon_0", "arakoon_1", "witness_0"]
arakoon_config_file = "%s/cfg/test.ini" % cwd

_arakoon_root = '/tmp/arakoon'

TLS = {
    'arakoon_config_file' : "%s/cfg/test_tls.ini" % cwd,
    'root_dir' : _arakoon_root,
}

for node in arakoon_nodes:
    TLS[node] = '%s/%s' % (_arakoon_root, node)



namespace = "demo"

N = 12
default_kind = "ASD"
