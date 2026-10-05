/* Native mqjs / readline: engine headers plus REPL libc interfaces. */
#include "translate/mquickjs_engine.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <sys/time.h>
#include "readline.h"
#include "readline_tty.h"
