# A file for the harness's own test: one of each verdict.
use lib.nu *
use std/assert

def "test passes" [] { assert equal 1 1 }
def "test fails" [] { assert equal 1 2 }
def "test skips" [] { skip "no reason at all" }
def "test writes only into scratch" [] { assert (scratch | str starts-with $env.TEST_SCRATCH) }
