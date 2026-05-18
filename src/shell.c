/*
 * shell.c — SHELL INTERACTIVO DE miniOS
 *
 * Este archivo implementa el prompt `miniOS>` y el parser de comandos.
 * El main loop (shell_run) y varios comandos (help, slice, inspect, runpair,
 * log) vienen ya implementados.
 *
 * Tu trabajo es implementar las CUATRO funciones marcadas con [TODO]:
 *   1. cmd_run         — validar path y lanzar proceso con el scheduler
 *   2. cmd_ps          — mostrar la process table (process status)
 *   3. cmd_kill_proc   — matar un proceso por PID
 *   4. cmd_stats       — mostrar metricas agregadas del scheduler
 *
 * Los comandos implementados (cmd_help, cmd_slice, cmd_inspect, cmd_runpair)
 * sirven como referencia de estilo, convenciones y manejo de argumentos.
 *
 * REGLAS IMPORTANTES:
 *   - Cualquier comando que LEA process_table o ready_queue debe envolverse
 *     en block_alarm() / unblock_alarm() para evitar race con scheduler_tick.
 *   - Usa las funciones auxiliares ya disponibles:
 *       pcb_print_table()  en pcb.h
 *       pcb_state_name()   en pcb.h
 *       rq_print()         en ready_queue.h
 *       rq_remove()        en ready_queue.h
 *       timer_get_slice()  en timer.h
 */

#include "shell.h"
#include "scheduler.h"
#include "timer.h"
#include "monitor.h"
#include "pcb.h"
#include "ready_queue.h"
#include "platform/platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/wait.h>

#define MAX_LINE 256

// ============================================================
// Helpers y comandos ya implementados — NO los modifiques
// ============================================================

// Block SIGALRM while modifying shared state
static sigset_t alarm_mask;

static void block_alarm(void)
{
    sigprocmask(SIG_BLOCK, &alarm_mask, NULL);
}

static void unblock_alarm(void)
{
    sigprocmask(SIG_UNBLOCK, &alarm_mask, NULL);
}

static void cmd_help(void)
{
    printf("\nComandos disponibles:\n");
    printf("  run <binario>       Lanzar un proceso nuevo\n");
    printf("  ps                  Mostrar tabla de procesos\n");
    printf("  kill <pid>          Terminar un proceso\n");
    printf("  slice <ms>          Cambiar time slice (50-5000 ms)\n");
    printf("  inspect <pid>       Ver registros de un proceso\n");
    printf("  runpair <nombre>    Lanzar par de procesos comunicantes\n");
    printf("  stats               Mostrar metricas del scheduler\n");
    printf("  log on|off          Activar/desactivar emision de eventos JSON\n");
    printf("  help                Mostrar esta ayuda\n");
    printf("  exit                Terminar todos los procesos y salir\n");
    printf("\n");
}

static void cmd_slice(const char *arg)
{
    if (!arg || strlen(arg) == 0)
    {
        printf("Time slice actual: %d ms\n", timer_get_slice());
        return;
    }

    int ms = atoi(arg);
    if (ms < 50 || ms > 5000)
    {
        printf("Error: time slice debe estar entre 50 y 5000 ms\n");
        return;
    }

    int old_ms = timer_get_slice();
    timer_set_slice(ms);
    if (scheduler_is_running())
    {
        timer_start();
    }
    monitor_emit_slice_changed(old_ms, ms);
    printf("Time slice cambiado a %d ms\n", ms);
}

static void cmd_inspect(const char *arg)
{
    if (!arg || strlen(arg) == 0)
    {
        printf("Uso: inspect <pid>\n");
        return;
    }

    int target_pid = atoi(arg);
    block_alarm();

    int found = 0;
    for (int i = 0; i < process_count; i++)
    {
        if (process_table[i].pid == target_pid)
        {
            found = 1;
            printf("\n=== PCB de PID %d (%s) ===\n", target_pid, process_table[i].name);
            printf("  Estado:           %s\n", pcb_state_name(process_table[i].state));
            printf("  CPU Time:         %.1f ms\n", process_table[i].cpu_time_ms);
            printf("  Waiting Time:     %.1f ms\n", process_table[i].wait_time_ms);
            printf("  Context Switches: %d\n", process_table[i].context_switches);

            if (platform_registers_available() && process_table[i].regs_valid)
            {
                printf("\n  === Registros ===\n");
                printf("  Program Counter: 0x%016llx\n", (unsigned long long)process_table[i].registers.program_counter);
                printf("  Stack Pointer:   0x%016llx\n", (unsigned long long)process_table[i].registers.stack_pointer);
                for (int r = 0; r < NUM_GENERAL_REGS; r++)
                {
                    printf("  Reg[%2d]:         0x%016llx\n", r,
                           (unsigned long long)process_table[i].registers.general_regs[r]);
                }
            }
            else if (!platform_registers_available())
            {
                printf("\n  [Registros no disponibles -- SIP habilitado en macOS]\n");
                printf("  Los registros estaran disponibles en WSL2/Linux.\n");
            }
            else
            {
                printf("\n  [Registros aun no capturados]\n");
            }
            printf("\n");
            break;
        }
    }

    if (!found)
    {
        printf("Proceso PID %d no encontrado.\n", target_pid);
    }

    unblock_alarm();
}

static void cmd_runpair(const char *name)
{
    if (!name || strlen(name) == 0)
    {
        printf("Uso: runpair <nombre>\n");
        printf("  Pares disponibles: ping_pong, productor_consumidor\n");
        return;
    }

    char server_path[128], client_path[128], sock_path[128];

    if (strcmp(name, "ping_pong") == 0)
    {
        snprintf(server_path, sizeof(server_path), "programs/bin/ping_pong_server");
        snprintf(client_path, sizeof(client_path), "programs/bin/ping_pong_client");
        snprintf(sock_path, sizeof(sock_path), "/tmp/minios_pingpong.sock");
    }
    else if (strcmp(name, "productor_consumidor") == 0)
    {
        snprintf(server_path, sizeof(server_path), "programs/bin/productor");
        snprintf(client_path, sizeof(client_path), "programs/bin/consumidor");
        snprintf(sock_path, sizeof(sock_path), "/tmp/minios_prodcons.sock");
    }
    else
    {
        printf("Par desconocido: '%s'\n", name);
        printf("  Pares disponibles: ping_pong, productor_consumidor\n");
        return;
    }

    if (access(server_path, X_OK) != 0)
    {
        printf("Error: '%s' no encontrado. Ejecuta 'make programs' primero.\n", server_path);
        return;
    }
    if (access(client_path, X_OK) != 0)
    {
        printf("Error: '%s' no encontrado. Ejecuta 'make programs' primero.\n", client_path);
        return;
    }

    unlink(sock_path);
    printf("Lanzando par '%s' con socket %s\n", name, sock_path);

    int idx1 = scheduler_create_process(server_path, sock_path);
    if (idx1 < 0)
        return;

    int idx2 = scheduler_create_process(client_path, sock_path);
    if (idx2 < 0)
        return;

    if (!scheduler_is_running())
    {
        scheduler_start(timer_get_slice());
    }
}

// ============================================================
// [TODO 1/4] cmd_run
// ------------------------------------------------------------
// Parsea el comando `run <path> [arg]`, valida la ruta y crea
// un proceso a traves del scheduler. Si es el primer proceso,
// arranca el scheduler con el slice actual.
//
// Ejemplo de uso:
//   miniOS> run programs/bin/countdown 10
// ============================================================
static void cmd_run(const char *path, const char *arg)
{
    // ---- PASO 1: Validar que se proporciono un path ----
    if (path == NULL || strlen(path) == 0)
    {
        // Si el usuario escribio solo "run" sin argumento
        printf("Uso: run <binario> [argumento]\n");
        return;
    }
    // ---- PASO 2: Validar que el archivo existe y es ejecutable ----
    // access(path, X_OK) verifica:
    //   - El archivo existe (caso contrario retorna -1)
    //   - El usuario tiene permiso de ejecucion (X_OK)
    // 0 = exito, cualquier otro valor = error.
    if (access(path, X_OK) != 0)
    {
        printf("Error: '%s' no encontrado o no es ejecutable.\n", path);
        return;
        // El error tipico: escribir mal la ruta o no haber hecho 'make'
    }
    // ---- PASO 3: Crear el proceso mediante el scheduler ----
    int idx = scheduler_create_process(path, arg);
    // scheduler_create_process() hace todo el trabajo pesado:
    //   - fork() + execl()
    //   - Detener con SIGSTOP
    //   - Crear PCB
    //   - Encolar en ready queue
    // Retorna el indice en process_table, o -1 si fallo.
    if (idx < 0)
        return; // scheduler_create_process ya imprimio el error
    // ---- PASO 4: Arrancar scheduler si es el primer proceso ----
    // scheduler_is_running() verifica la variable global scheduler_active.
    // rq_is_empty() verifica si la ready queue tiene procesos.
    // Si el scheduler NO esta corriendo PERO hay procesos en cola
    // (acabamos de meter uno), entonces lo arrancamos.
    if (!scheduler_is_running() && !rq_is_empty())
    {
        // timer_get_slice() devuelve el time slice actual (default 500ms)
        scheduler_start(timer_get_slice());
        // scheduler_start() desencola el primer proceso, lo reanuda
        // y arranca el timer periodico. A partir de aqui, todo
        // es automatico: SIGALRM -> scheduler_tick -> context switch
    }
    (void)path;
    (void)arg; // silence unused while unimplemented
}

// ============================================================
// [TODO 2/4] cmd_ps
// ------------------------------------------------------------
// Muestra la tabla de procesos con PCBs y la ready queue.
// Debe invocar block_alarm antes de leer la process_table y
// unblock_alarm al terminar.
//
// Formato esperado (puedes usar pcb_print_table() que ya lo hace):
//   PID    NOMBRE           ESTADO          CPU(ms) ESPERA(ms)  SWITCHES
//   -------------------------------------------------------------------
//   1234   countdown        RUNNING            1520.3      120.0       3
//   1235   primos           READY              1480.5      460.1       3
//
// Y tras la tabla, mostrar el contenido de la ready queue usando
// rq_print() (que imprime algo como "Ready Queue: PID 1235 -> PID 1234").
// ============================================================
static void cmd_ps(void)
{
    // ---- PASO 1: Bloquear SIGALRM ----
    block_alarm();
    // Mientras mostramos la tabla, NO queremos que scheduler_tick
    // modifique process_table o la ready queue.
    // Si SIGALRM llega mientras, queda pendiente y se entrega
    // cuando llamemos unblock_alarm().
    // ---- PASO 2: Si no hay procesos, mostrar mensaje ----
    if (process_count == 0)
    {
        printf("No hay procesos.\n");
        unblock_alarm(); // IMPORTANTE: desbloquear antes de retornar
        return;
    }
    // ---- PASO 3: Mostrar la tabla de procesos ----
    printf("\n");
    pcb_print_table();
    // pcb_print_table() imprime las columnas:
    //   PID    NOMBRE           ESTADO     CPU(ms)  ESPERA(ms)  SWITCHES
    //   -----------------------------------------------------------------
    //   1234   countdown        RUNNING     1520.3      120.0         3
    //   1235   primos           READY       1480.5      460.1         3
    //
    // El estado aparece con colores ANSI:
    //   - READY:    amarillo
    //   - RUNNING:  verde
    //   - TERMINATED: gris
    //   - BLOCKED:  rojo
    // ---- PASO 4: Mostrar la ready queue ----
    printf("\n");
    rq_print();
    // rq_print() imprime el contenido de la cola circular:
    //   Ready Queue: PID 1234 -> PID 1235
    // Muestra el orden en que los procesos recibiran CPU.
    // El primero (izquierda) es el siguiente en ejecutar.
    printf("\n");
    // ---- PASO 5: Desbloquear SIGALRM ----
    unblock_alarm();
}

// ============================================================
// [TODO 3/4] cmd_kill_proc
// ------------------------------------------------------------
// Recibe un PID como string, busca el proceso en process_table y
// lo termina con SIGKILL. Debe remover el proceso de la ready queue
// y marcar su PCB como PROC_TERMINATED.
//
// Nota: El SIGCHLD handler del scheduler recogera el proceso, pero
// es recomendable hacer waitpid aqui tambien para liberar recursos
// inmediatamente y que `ps` refleje el cambio al instante.
// ============================================================
static void cmd_kill_proc(const char *arg)
{
    // ---- PASO 1: Validar argumento ----
    if (arg == NULL || strlen(arg) == 0)
    {
        printf("Uso: kill <pid>\n");
        return;
    }
    // ---- PASO 2: Convertir string a entero ----
    int target_pid = atoi(arg);
    // atoi() convierte "1234" a 1234.
    // Si el string no es numerico, atoi retorna 0.
    // Los PIDs siempre son > 0, asi que 0 es invalido.
    if (target_pid <= 0)
    {
        printf("PID invalido.\n");
        return;
    }
    // ---- PASO 3: Bloquear SIGALRM ----
    block_alarm();
    // Protegemos el acceso a process_table y ready queue.
    // ---- PASO 4: Buscar y matar el proceso ----
    int found = 0;
    // Bandera para saber si encontramos el PID.
    for (int i = 0; i < process_count; i++)
    {
        // Recorremos toda la process_table buscando el PID
        if (process_table[i].pid == target_pid &&
            process_table[i].state != PROC_TERMINATED)
        {
            // Solo si NO esta ya terminado
            // 4a: Enviar SIGKILL
            // SIGKILL es la señal de muerte FORZADA.
            // El proceso NO puede ignorarla, capturarla ni bloquearla.
            // El kernel lo elimina inmediatamente.
            kill(target_pid, SIGKILL);
            // 4b: waitpid() para evitar zombies
            // Cuando un proceso muere, queda en estado ZOMBIE hasta
            // que el padre llame waitpid() para recolectar su codigo
            // de salida. Si no hacemos waitpid, el proceso queda como
            // "defunct" en el sistema.
            int status;
            waitpid(target_pid, &status, 0);
            // Flags=0: bloqueante. Espera a que el proceso sea recolectado.
            // 4c: Actualizar PCB
            process_table[i].state = PROC_TERMINATED;
            // El proceso ya no esta activo en nuestro scheduler.
            // 4d: Remover de la ready queue
            rq_remove(i);
            // Si el proceso estaba esperando en la cola, lo sacamos.
            // Si era el RUNNING actual, el handler SIGCHLD ya se
            // encargara de despachar al siguiente.
            printf("Proceso PID %d terminado.\n", target_pid);
            found = 1;
            break; // Salir del for, ya encontramos el PID
        }
    }
    // ---- PASO 5: Si no se encontro ----
    if (!found)
    {
        printf("PID %d no encontrado o ya terminado.\n", target_pid);
    }
    // ---- PASO 6: Desbloquear SIGALRM ----
    unblock_alarm();

    (void)arg; // silence unused while unimplemented
}

// ============================================================
// [TODO 4/4] cmd_stats
// ------------------------------------------------------------
// Muestra metricas agregadas del scheduler:
//   - Cantidad de procesos activos y terminados
//   - Time slice actual
//   - CPU total acumulado (suma de cpu_time_ms de todos)
//   - Context switches totales
//   - Promedios (CPU y espera) por proceso
//
// Formato sugerido:
//
//   === Estadisticas del Scheduler ===
//     Procesos activos:      2
//     Procesos terminados:   1
//     Time slice actual:     500 ms
//     CPU total acumulado:   3450.2 ms
//     Context switches:      12
//     Avg CPU por proceso:   1150.1 ms
//     Avg espera:            230.5 ms
// ============================================================
static void cmd_stats(void)
{
    // ---- PASO 1: Bloquear SIGALRM ----
    block_alarm();
    // ---- PASO 2: Declarar e inicializar acumuladores ----
    int active = 0;         // Procesos en READY o RUNNING
    int terminated = 0;     // Procesos que ya terminaron
    double total_cpu = 0;   // CPU time acumulada de TODOS los procesos
    double total_wait = 0;  // Wait time acumulado de TODOS los procesos
    int total_switches = 0; // Context switches totales del sistema
    // ---- PASO 3: Recorrer la process_table sumando ----
    for (int i = 0; i < process_count; i++)
    {
        // Clasificar: activo o terminado
        if (process_table[i].state == PROC_TERMINATED)
            terminated++;
        else
            active++;
        // Acumular metricas
        total_cpu += process_table[i].cpu_time_ms;
        total_wait += process_table[i].wait_time_ms;
        total_switches += process_table[i].context_switches;
    }
    // ---- PASO 4: Imprimir las estadisticas ----
    printf("\n=== Estadisticas del Scheduler ===\n");
    printf("  Procesos activos:      %d\n", active);
    // Procesos que aun estan en ejecucion o esperando turno.
    printf("  Procesos terminados:   %d\n", terminated);
    // Procesos que ya completaron su ejecucion.
    printf("  Time slice actual:     %d ms\n", timer_get_slice());
    // Cuanto dura cada turno de CPU (configurable con 'slice').
    printf("  CPU total acumulado:   %.1f ms\n", total_cpu);
    // Suma de todo el tiempo que todos los procesos han usado la CPU.
    printf("  Context switches:      %d\n", total_switches);
    // Cuantas veces se ha cambiado de proceso en la CPU.
    if (process_count > 0)
    {
        // Promedios: solo si hay procesos (evitar division por cero)
        printf("  Avg CPU por proceso:   %.1f ms\n", total_cpu / process_count);
        // Tiempo promedio que cada proceso ha usado la CPU.
        printf("  Avg espera:            %.1f ms\n", total_wait / process_count);
        // Tiempo promedio que cada proceso ha esperado en la ready queue.
    }
    printf("\n");
    // ---- PASO 5: Desbloquear SIGALRM ----
    unblock_alarm();
}

// ============================================================
// Main loop del shell — ya implementado, NO lo modifiques
// ============================================================
void shell_run(void)
{
    char line[MAX_LINE];

    // Setup alarm mask for sigprocmask
    sigemptyset(&alarm_mask);
    sigaddset(&alarm_mask, SIGALRM);

    printf("+----------------------------------+\n");
    printf("|       miniOS v1.0                |\n");
    printf("|   Simulador de Context Switching |\n");
    printf("|   Escribe 'help' para ayuda      |\n");
    printf("+----------------------------------+\n\n");

    while (1)
    {
        printf("miniOS> ");
        fflush(stdout);

        if (fgets(line, sizeof(line), stdin) == NULL)
        {
            printf("\n");
            break;
        }

        size_t len = strlen(line);
        if (len > 0 && line[len - 1] == '\n')
            line[len - 1] = '\0';

        if (strlen(line) == 0)
            continue;

        char *cmd = strtok(line, " \t");
        char *arg = strtok(NULL, " \t");
        char *arg2 = strtok(NULL, " \t");

        if (!cmd)
            continue;

        if (strcmp(cmd, "help") == 0)
        {
            cmd_help();
        }
        else if (strcmp(cmd, "run") == 0)
        {
            block_alarm();
            cmd_run(arg, arg2);
            unblock_alarm();
        }
        else if (strcmp(cmd, "ps") == 0)
        {
            cmd_ps();
        }
        else if (strcmp(cmd, "kill") == 0)
        {
            cmd_kill_proc(arg);
        }
        else if (strcmp(cmd, "slice") == 0)
        {
            cmd_slice(arg);
        }
        else if (strcmp(cmd, "inspect") == 0)
        {
            cmd_inspect(arg);
        }
        else if (strcmp(cmd, "runpair") == 0)
        {
            block_alarm();
            cmd_runpair(arg);
            unblock_alarm();
        }
        else if (strcmp(cmd, "stats") == 0)
        {
            cmd_stats();
        }
        else if (strcmp(cmd, "log") == 0)
        {
            if (!arg || strlen(arg) == 0)
            {
                printf("Log esta %s. Uso: log on|off\n",
                       monitor_is_enabled() ? "activado" : "desactivado");
            }
            else if (strcmp(arg, "on") == 0)
            {
                monitor_init(MONITOR_SOCKET_PATH);
                monitor_set_enabled(1);
            }
            else if (strcmp(arg, "off") == 0)
            {
                monitor_set_enabled(0);
                printf("Log desactivado.\n");
            }
            else
            {
                printf("Uso: log on|off\n");
            }
        }
        else if (strcmp(cmd, "exit") == 0)
        {
            block_alarm();
            scheduler_stop();
            monitor_close();
            unblock_alarm();
            printf("Hasta luego.\n");
            break;
        }
        else
        {
            printf("Comando desconocido: '%s'. Escribe 'help' para ver comandos.\n", cmd);
        }
    }
}
