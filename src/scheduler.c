/*
 * scheduler.c — ESQUELETO DEL LABORATORIO
 *
 * Este archivo contiene el núcleo del scheduler round-robin de miniOS.
 * Las funciones de infraestructura (init, getters, install_sigchld, stop,
 * timespec_diff_ms) ya están implementadas.
 *
 * Tu trabajo es implementar las CUATRO funciones marcadas con [TODO]:
 *   1. scheduler_create_process  — fork + exec + SIGSTOP + PCB init
 *   2. scheduler_start           — arrancar el primer proceso y el timer
 *   3. scheduler_tick            — handler de SIGALRM (context switch)
 *   4. scheduler_sigchld         — handler de SIGCHLD (terminación)
 *
 * Cada función viene con comentarios numerados que describen el flujo
 * paso a paso. Tu trabajo es traducir cada paso a código C usando las
 * APIs de POSIX y las funciones de infraestructura disponibles.
 *
 * APIs disponibles:
 *   - POSIX:       fork, execl, waitpid, kill, clock_gettime
 *   - platform_*:  ver src/platform/platform.h
 *   - pcb_*:       ver src/pcb.h
 *   - rq_*:        ver src/ready_queue.h
 *   - timer_*:     ver src/timer.h
 *   - monitor_*:   ver src/monitor.h
 *
 * REGLAS DE SEGURIDAD EN SEÑALES (importantes para scheduler_tick y
 * scheduler_sigchld):
 *   - NO uses printf/fprintf dentro de los handlers (no son
 *     async-signal-safe). Solo kill, waitpid, clock_gettime, write.
 *   - El shell bloquea SIGALRM con sigprocmask durante sus operaciones
 *     críticas, por lo que no necesitas mutex manual sobre process_table.
 */

#include "scheduler.h"
#include "timer.h"
#include "monitor.h"
#include "platform/platform.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <libgen.h>

// Estado global del scheduler
static volatile int current_running = -1; // índice en process_table del proceso RUNNING, -1 si ninguno
static volatile int scheduler_active = 0; // 1 si el scheduler está corriendo

// ============================================================
// Helpers ya implementados — NO los modifiques
// ============================================================

double timespec_diff_ms(struct timespec end, struct timespec start)
{
    double sec = (double)(end.tv_sec - start.tv_sec);
    double nsec = (double)(end.tv_nsec - start.tv_nsec);
    return sec * 1000.0 + nsec / 1000000.0;
}

void scheduler_init(void)
{
    process_count = 0;
    current_running = -1;
    scheduler_active = 0;
    rq_init();
}

int scheduler_get_running(void)
{
    return current_running;
}

int scheduler_is_running(void)
{
    return scheduler_active;
}

void scheduler_install_sigchld(void)
{
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = scheduler_sigchld;
    sa.sa_flags = SA_RESTART | SA_NOCLDSTOP;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGCHLD, &sa, NULL);
}

void scheduler_stop(void)
{
    timer_stop();
    scheduler_active = 0;

    for (int i = 0; i < process_count; i++)
    {
        if (process_table[i].state != PROC_TERMINATED)
        {
            kill(process_table[i].pid, SIGKILL);
            int status;
            waitpid(process_table[i].pid, &status, 0);
            process_table[i].state = PROC_TERMINATED;
        }
    }
    current_running = -1;
}

// ============================================================
// [TODO 1/4] scheduler_create_process
// ------------------------------------------------------------
// Crea un proceso nuevo a partir de un binario, lo deja detenido
// con estado PROC_READY y lo encola en la ready queue.
//
// Retorna el índice del nuevo PCB en process_table, o -1 en error.
//
// Observable correcto: `ps aux | grep <binario>` debe mostrar el
// proceso en estado T (stopped) justo después de crearlo.
// ============================================================
int scheduler_create_process(const char *path, const char *arg)
{
    // ---- PASO 1: Validar que hay espacio en la tabla de procesos ----
    // MAX_PROCESSES = 10. Si la tabla esta llena, no podemos crear mas.
    if (process_count >= MAX_PROCESSES)
    {
        fprintf(stderr, "Error: tabla de procesos llena (%d max)\n", MAX_PROCESSES);
        return -1; // Retorna -1 para indicar error
    }
    // ---- PASO 2: Llamar fork() ----
    // fork() crea un proceso hijo identico al padre.
    // En el hijo retorna 0, en el padre retorna el PID del hijo.
    pid_t pid = fork();

    // Si fork() retorna negativo, hubo error (ej. memoria insuficiente)
    if (pid < 0)
    {
        perror("fork"); // Imprime el error del sistema
        return -1;
    }
    // ---- PASO 3: Codigo del HIJO (pid == 0) ----
    if (pid == 0)
    { // Estamos dentro del proceso hijo
        // 3a: Si la plataforma usa ptrace (Linux), hay que habilitar
        //     el tracing ANTES de hacer exec. El hijo le dice al kernel:
        //     "quiero que mi padre pueda inspeccionarme".
        if (platform_uses_ptrace())
            platform_trace_child();
        // 3b: execl() reemplaza TODO el proceso hijo con el binario 'path'.
        //     El primer parametro es el path del ejecutable.
        //     El segundo parametro es argv[0] (por convencion, el path mismo).
        //     El tercero es el argumento (si existe).
        //     El ultimo debe ser NULL para marcar el fin de argumentos.
        if (arg != NULL)
            execl(path, path, arg, NULL); // Con argumento
        else
            execl(path, path, NULL); // Sin argumento
        // 3c: Si execl() RETORNA, significa que FALLO.
        //     execl solo retorna en caso de error.
        //     Usamos _exit() y no exit() porque es una funcion
        //     async-signal-safe (segura para usar despues de fork).
        perror("execl");
        _exit(1);
    }
    // ---- PASO 4: Codigo del PADRE (pid > 0) ----
    // NOTA: El codigo de aqui en adelante SOLO lo ejecuta el padre.
    // 4a: Si la plataforma usa ptrace, esperamos que el hijo se detenga
    //     con SIGTRAP justo despues del exec.
    //     waitpid con flags=0 es BLOQUEANTE (espera hasta que el hijo cambie de estado).
    int status;
    if (platform_uses_ptrace())
    {
        waitpid(pid, &status, 0); // Espera al SIGTRAP del hijo
        // Verificamos que el hijo efectivamente este DETENIDO (no terminado).
        // WIFSTOPPED(status) retorna verdadero si el hijo recibio una señal
        // que lo detuvo (SIGTRAP, SIGSTOP, etc.).
        if (!WIFSTOPPED(status))
        {
            // Si no esta detenido, algo salio mal: matamos al hijo y retornamos error.
            kill(pid, SIGKILL);
            return -1;
        }
    }
    // ---- PASO 5: Crear la entrada en el PCB (Process Control Block) ----
    int idx = process_count; // El indice libre es el actual contador
    // strdup() duplica el string path en memoria nueva (malloc internamente).
    // basename() extrae el nombre del archivo sin la ruta.
    // Ejemplo: "programs/bin/countdown" -> "countdown"
    char *path_copy = strdup(path);
    char *short_name = basename(path_copy);

    // pcb_init() llena la estructura pcb_t:
    //   - pid = el PID del hijo
    //   - name = "countdown" (nombre corto)
    //   - state = PROC_NEW
    //   - cpu_time_ms = 0
    //   - context_switches = 0
    //   - created_at = clock_gettime() actual
    pcb_init(&process_table[idx], pid, short_name);
    
    // ---- PASO 6: Capturar registros iniciales (solo Linux/ptrace) ----
    if (platform_uses_ptrace())
    {
        // platform_get_registers() lee los registros de CPU del hijo
        // (Program Counter, Stack Pointer, registros generales)
        // usando PTRACE_GETREGS. Retorna 0 si tuvo exito.
        if (platform_get_registers(pid, &process_table[idx].registers) == 0)
            process_table[idx].regs_valid = 1; // Marca que los registros son validos

        // Detach: libera el tracing del hijo para que pueda ejecutarse
        // sin ser monitoreado (a menos que lo volvamos a attachar).
        platform_detach(pid);
    }
    // ---- PASO 7: Detener el proceso con SIGSTOP ----
    // platform_stop_process() envia SIGSTOP al proceso.
    // SIGSTOP es una señal que el proceso NO puede ignorar ni capturar.
    // El kernel pone el proceso en estado 'T' (stopped).
    if (platform_stop_process(pid) != 0)
    {
        perror("platform_stop_process");
        kill(pid, SIGKILL); // Si falla, matamos el proceso
        return -1;
    }
    // ---- PASO 8: Confirmar que el proceso se detuvo ----
    // WUNTRACED: flag que hace que waitpid tambien reporte hijos
    // detenidos por SIGSTOP (no solo terminaciones).
    waitpid(pid, &status, WUNTRACED);
    // ---- PASO 9: Marcar PCB como READY y encolar ----
    process_table[idx].state = PROC_READY;
    // El proceso esta en estado READY: listo para ejecutar,
    // esperando su turno en la ready queue.
    process_count++; // IMPORTANTE: incrementar el contador global
    // Ahora este proceso es visible en la process_table.
    rq_enqueue(idx); // Meter el indice al FINAL de la ready queue
    // La ready queue es una cola circular FIFO.
    // El scheduler sacara procesos del frente cuando toque su turno.
    // Emitir evento PROCESS_CREATED al monitor (dashboard web)
    monitor_emit_created(pid, short_name);
    // Si capturamos registros, emitir tambien evento REGISTERS
    if (process_table[idx].regs_valid)
        monitor_emit_registers(pid,
                               process_table[idx].registers.program_counter,
                               process_table[idx].registers.stack_pointer);
    free(path_copy); // Liberamos la copia duplicada (despues de usarla)
    return idx; // Retorna el indice del PCB creado

}

// ============================================================
// [TODO 2/4] scheduler_start
// ------------------------------------------------------------
// Arranca el scheduler: desencola el primer proceso, lo pone en
// RUNNING, le manda SIGCONT e instala el timer que dispara el
// context switch periódicamente.
//
// Observable correcto: tras crear 1 proceso y llamar start, ese
// proceso empieza a producir salida en la terminal.
// ============================================================
void scheduler_start(int slice_ms)
{
    // ---- PASO 1: Verificar que hay procesos listos ----
    if (rq_is_empty())
    {
        printf("No hay procesos en la ready queue.\n");
        return; // No hay nada que schedulear
    }
    // ---- PASO 2: Desencolar el primer proceso ----
    // rq_dequeue() saca el indice del FRENTE de la cola circular.
    // La cola es FIFO: el primero en llegar es el primero en ejecutar.
    int idx = rq_dequeue();
    // ---- PASO 3: Actualizar el PCB del proceso entrante ----
    process_table[idx].state = PROC_RUNNING;
    // Cambia de READY a RUNNING: ahora esta usando la CPU.
    clock_gettime(CLOCK_MONOTONIC, &process_table[idx].last_started);
    // Registra el timestamp ACTUAL como "ultimo inicio".
    // CLOCK_MONOTONIC es un reloj que siempre avanza hacia adelante
    // (no se ve afectado por cambios de hora del sistema).
    // Este timestamp se usara en scheduler_tick para calcular
    // cuanto tiempo uso la CPU este proceso.
    current_running = idx;
    // Variable global que indica QUE indice de process_table
    // esta usando la CPU actualmente.
    // ---- PASO 4: Reanudar el proceso ----
    // platform_resume_process() envia SIGCONT al proceso.
    // El kernel lo mueve de estado 'T' (stopped) a 'R' (running).
    // El proceso CONTINUA ejecutando desde donde se detuvo.
    platform_resume_process(process_table[idx].pid);
    // ---- PASO 5: Activar scheduler y timer ----
    scheduler_active = 1;
    // Bandera global: indica que el scheduler esta corriendo.
    timer_init(slice_ms, scheduler_tick);
    // Configura el timer:
    //   - slice_ms: cuanto dura cada time slice en milisegundos
    //   - scheduler_tick: la funcion que se llamara en cada SIGALRM
    // timer_init() internamente hace sigaction() para instalar
    // scheduler_tick como el handler de la señal SIGALRM.
    timer_start();
    // Arranca setitimer(ITIMER_REAL):
    //   - Envia SIGALRM cada 'slice_ms' milisegundos
    //   - Es un timer PERIODICO (se reinicia solo)
    //   - Cuando SIGALRM llega, el kernel interrumpe lo que sea
    //     que este haciendo el proceso actual y ejecuta scheduler_tick

}

// ============================================================
// [TODO 3/4] scheduler_tick  — handler de SIGALRM
// ------------------------------------------------------------
// Se invoca CADA vez que expira el time slice. Realiza el
// context switch: detiene al proceso actual, actualiza su PCB,
// lo manda al final de la cola, saca al siguiente y lo reanuda.
//
// ¡IMPORTANTE! Esta función corre en un signal handler.
//   - NO llames printf/fprintf/malloc.
//   - Solo kill, waitpid, clock_gettime, write son seguros.
//   - Las funciones monitor_emit_* internamente usan snprintf + write,
//     que es aceptable para este proyecto educativo.
//
// Observable correcto: el Gantt chart del dashboard muestra
// segmentos alternados entre procesos cada ~slice_ms.
// ============================================================
void scheduler_tick(int signum)
{
    (void)signum;

    // ---- PASO 1: Salida temprana si no hay proceso activo ----
    if (current_running < 0 || !scheduler_active)
        return;
    // Si nadie esta corriendo o el scheduler esta apagado,
    // no hay nada que hacer. Esto evita errores si SIGALRM
    // llega justo despues de scheduler_stop().
    // ---- PASO 2: Obtener puntero al PCB del proceso actual ----
    pcb_t *current = &process_table[current_running];
    // current apunta al PCB del proceso que esta usando la CPU.
    // Usamos puntero para no copiar toda la estructura.
    // ---- PASO 3: DETENER el proceso actual ----
    platform_stop_process(current->pid);
    // Envia SIGSTOP. El kernel detiene el proceso inmediatamente.
    // El proceso queda en estado 'T' (stopped).
    // Cualquier instruccion que estuviera ejecutando se pausa.
    // ---- PASO 4: Actualizar PCB del proceso SALIENTE ----
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    // Obtiene el timestamp actual.
    double elapsed = timespec_diff_ms(now, current->last_started);
    // Calcula CUANTO TIEMPO estuvo este proceso usando la CPU
    // desde que arranco (o desde el ultimo context switch).
    current->cpu_time_ms += elapsed;
    // Acumula el tiempo de CPU total de este proceso.
    current->state = PROC_READY;
    // Vuelve a estado READY porque ya no esta usando la CPU.
    current->context_switches++;
    // Incrementa el contador de cambios de contexto.
    // Cada vez que el proceso cede la CPU (voluntaria o forzadamente)
    // se cuenta como un context switch.
    // ---- PASO 5: Encolar el proceso SALIENTE ----
    rq_enqueue(current_running);
    // Lo pone al FINAL de la ready queue.
    // Como es round-robin, todos los procesos rotan:
    // el que acaba de usar la CPU va al final de la cola.
    // ---- PASO 6: Verificar si la cola quedo vacia ----
    if (rq_is_empty())
    {
        current_running = -1;
        // Nadie corriendo.
        timer_stop();
        // Detiene el timer. setitimer(ITIMER_REAL) con valor 0
        // desactiva el timer periodico.
        return;
        // No hay mas procesos que schedulear por ahora.
    }
    // ---- PASO 7: Despachar el SIGUIENTE proceso ----
    int next_idx = rq_dequeue();
    // Saca el PROCESO del FRENTE de la cola.
    // Como la cola es FIFO, el que mas tiempo lleva esperando
    // es el que sigue.
    pcb_t *next = &process_table[next_idx];
    // Puntero al PCB del proceso entrante.
    next->state = PROC_RUNNING;
    // Cambia a RUNNING: ahora este proceso usara la CPU.
    clock_gettime(CLOCK_MONOTONIC, &next->last_started);
    // Registra el timestamp actual como su "ultimo inicio".
    // Cuando este proceso sea interrumpido, calcularemos
    // cuanto tiempo uso la CPU desde este momento.
    platform_resume_process(next->pid);
    // Envia SIGCONT al proceso entrante.
    // El kernel lo reanuda desde donde estaba detenido.
    // Emitir evento CONTEXT_SWITCH al dashboard
    monitor_emit_switch(current->pid, next->pid, timer_get_slice());
    // Envia al monitor: "el proceso A cedio la CPU al proceso B"
    // con el time slice actual. El dashboard usa esto para
    // dibujar el Gantt chart.
    current_running = next_idx;
    // Actualiza la variable global: ahora este es el RUNNING.
}

// ============================================================
// [TODO 4/4] scheduler_sigchld  — handler de SIGCHLD
// ------------------------------------------------------------
// Se invoca cuando un proceso hijo termina. Debe:
//   - Detectar TODOS los hijos terminados (puede haber varios).
//   - Actualizar su PCB a PROC_TERMINATED.
//   - Si el proceso que terminó era el RUNNING, despachar al siguiente.
//   - Si estaba en la ready queue, removerlo con rq_remove().
//
// Observable correcto: tras `exit` en miniOS, `ps aux | grep defunct`
// no muestra zombies.
// ============================================================
void scheduler_sigchld(int signum)
{
    (void)signum;

    int status;
    pid_t pid;
    // ---- PASO 1: Loop de recoleccion ----
    // waitpid(-1, ...) espera a CUALQUIER hijo.
    // WNOHANG: NO BLOQUEANTE. Si no hay hijos terminados,
    //          retorna 0 inmediatamente.
    // WUNTRACED: tambien reporta hijos detenidos (los ignoraremos).
    // El while es importante porque MULTIPLES hijos pueden
    // terminar al mismo tiempo y el kernel puede fusionar
    // varias señales SIGCHLD en una sola.
    while ((pid = waitpid(-1, &status, WNOHANG | WUNTRACED)) > 0)
    {
        // ---- PASO 2: Ignorar solo detenidos (no terminados) ----
        // WIFEXITED: true si el hijo termino con exit() o return.
        // WIFSIGNALED: true si el hijo fue matado por una señal.
        // Si ninguna de las dos es true, el hijo solo se detuvo
        // (ej. recibio SIGSTOP o SIGTRAP), no termino.
        if (!WIFEXITED(status) && !WIFSIGNALED(status))
            continue; // Ignorar y seguir al siguiente hijo
        // ---- PASO 3: Buscar el PID en la process_table ----
        for (int i = 0; i < process_count; i++)
        {
            if (process_table[i].pid != pid)
                continue; // No es este, seguir buscando
            if (process_table[i].state == PROC_TERMINATED)
                break; // Ya estaba marcado, saltar
            // ---- PASO 4: Marcar como TERMINATED ----
            process_table[i].state = PROC_TERMINATED;
            // Emitir evento PROCESS_TERMINATED al dashboard
            monitor_emit_terminated(pid,
                                    process_table[i].cpu_time_ms,
                                    process_table[i].context_switches);
            // ---- PASO 5: Si era el RUNNING ----
            if (i == current_running)
            {
                // 5a: Actualizar CPU time (desde ultimo last_started hasta ahora)
                struct timespec now;
                clock_gettime(CLOCK_MONOTONIC, &now);
                process_table[i].cpu_time_ms +=
                    timespec_diff_ms(now, process_table[i].last_started);
                current_running = -1;
                // Ya no hay proceso corriendo
                // 5b: Si hay procesos en cola, despachar al siguiente
                //     INMEDIATAMENTE (no esperar al proximo tick).
                if (!rq_is_empty())
                {
                    int next = rq_dequeue();
                    process_table[next].state = PROC_RUNNING;
                    clock_gettime(CLOCK_MONOTONIC,
                                  &process_table[next].last_started);
                    platform_resume_process(process_table[next].pid);
                    current_running = next;
                }
                else
                {
                    // No hay mas procesos: detener el timer
                    timer_stop();
                    scheduler_active = 0;
                }
                // ---- PASO 6: Si NO era el RUNNING (estaba en cola) ----
            }
            else
            {
                // Sacarlo de la ready queue con rq_remove()
                // Esta funcion busca el indice en la cola circular
                // y lo elimina, reconstruyendo la cola.
                rq_remove(i);
            }
            break; // Salir del for, ya procesamos este PID
        }
    }
    // Al salir del while, todos los hijos terminados fueron procesados.
    // No quedan zombies: waitpid los recolecto a todos.
}