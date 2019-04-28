// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2019 Sultan Alsawaf <sultan@kerneltoast.com>.
 */

#define pr_fmt(fmt) "simple_lmk: " fmt

#include <linux/kthread.h>
#include <linux/mm.h>
#include <linux/moduleparam.h>
#include <linux/oom.h>
#include <linux/sort.h>
#include <linux/version.h>

/* The sched_param struct is located elsewhere in newer kernels */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 10, 0)
#include <uapi/linux/sched/types.h>
#endif

/* SEND_SIG_FORCED isn't present in newer kernels */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 19, 0)
#define SIG_INFO_TYPE SEND_SIG_FORCED
#else
#define SIG_INFO_TYPE SEND_SIG_PRIV
#endif

/* The minimum number of pages to free per reclaim */
#define MIN_FREE_PAGES (CONFIG_ANDROID_SIMPLE_LMK_MINFREE * SZ_1M / PAGE_SIZE)

/* Kill up to this many victims per reclaim */
#define MAX_VICTIMS 64

struct victim_info {
	struct task_struct *tsk;
	unsigned long size;
};

/* Pulled from the Android framework */
static const short int adj_prio[] = {
	906, /* CACHED_APP_MAX_ADJ */
	905, /* Cached app */
	904, /* Cached app */
	903, /* Cached app */
	902, /* Cached app */
	901, /* Cached app */
	900, /* CACHED_APP_MIN_ADJ */
	800, /* SERVICE_B_ADJ */
	700, /* PREVIOUS_APP_ADJ */
	600, /* HOME_APP_ADJ */
	500, /* SERVICE_ADJ */
	400, /* HEAVY_WEIGHT_APP_ADJ */
	300, /* BACKUP_APP_ADJ */
	200, /* PERCEPTIBLE_APP_ADJ */
	100, /* VISIBLE_APP_ADJ */
	0    /* FOREGROUND_APP_ADJ */
};

static DECLARE_WAIT_QUEUE_HEAD(oom_waitq);
static atomic_t oom_count = ATOMIC_INIT(0);

static int victim_info_cmp(const void *lhs_ptr, const void *rhs_ptr)
{
	const struct victim_info *lhs = (typeof(lhs))lhs_ptr;
	const struct victim_info *rhs = (typeof(rhs))rhs_ptr;

	if (lhs->size > rhs->size)
		return -1;

	if (lhs->size < rhs->size)
		return 1;

	return 0;
}

static bool mm_is_duplicate(struct victim_info *varr, int vlen,
			    struct mm_struct *mm)
{
	int i;

	for (i = 0; i < vlen; i++) {
		struct victim_info *victim = varr + i;

		if (victim->tsk->mm == mm)
			return true;
	}

	return false;
}

static bool vtsk_is_duplicate(struct victim_info *varr, int vlen,
			      struct task_struct *vtsk)
{
	int i;

	for (i = 0; i < vlen; i++) {
		struct victim_info *victim = varr + i;

		if (same_thread_group(victim->tsk, vtsk))
			return true;
	}

	return false;
}

static unsigned long find_victims(struct victim_info *varr, int *vindex,
				  int vmaxlen, int min_adj, int max_adj)
{
	unsigned long pages_found = 0;
	int old_vindex = *vindex;
	struct task_struct *tsk;

	for_each_process(tsk) {
		struct task_struct *vtsk;
		unsigned long tasksize;
		short oom_score_adj;

		/* Make sure there's space left in the victim array */
		if (*vindex == vmaxlen)
			break;

		/* Don't kill current, kthreads, init, or duplicates */
		if (same_thread_group(tsk, current) ||
		    tsk->flags & PF_KTHREAD ||
		    is_global_init(tsk) ||
		    vtsk_is_duplicate(varr, *vindex, tsk))
			continue;

		vtsk = find_lock_task_mm(tsk);
		if (!vtsk)
			continue;

		/* Skip tasks that lack memory or have a redundant mm */
		if (test_tsk_thread_flag(vtsk, TIF_MEMDIE) ||
		    mm_is_duplicate(varr, *vindex, vtsk->mm))
			goto unlock_mm;

		/* Check the task's importance (adj) to see if it's in range */
		oom_score_adj = vtsk->signal->oom_score_adj;
		if (oom_score_adj < min_adj || oom_score_adj > max_adj)
			goto unlock_mm;

		/* Get the total number of physical pages in use by the task */
		tasksize = get_mm_rss(vtsk->mm);
		if (!tasksize)
			goto unlock_mm;

		/* Store this potential victim away for later */
		get_task_struct(vtsk);
		varr[*vindex].tsk = vtsk;
		varr[*vindex].size = tasksize;
		(*vindex)++;

		/* Keep track of the number of pages that have been found */
		pages_found += tasksize;
		continue;

unlock_mm:
		task_unlock(vtsk);
	}

	/*
	 * Sort the victims in descending order of size to prioritize killing
	 * the larger ones first.
	 */
	if (pages_found)
		sort(varr + old_vindex, *vindex - old_vindex, sizeof(*varr),
		     victim_info_cmp, NULL);

	return pages_found;
}

static void kill_vtsk(struct task_struct *vtsk, wait_queue_head_t *victim_waitq,
		      atomic_t *victim_count)
{
	/* Configure the victim's mm to notify us when it's freed */
	vtsk->mm->slmk_waitq = victim_waitq;
	vtsk->mm->slmk_counter = victim_count;

#ifdef CONFIG_ANDROID_SIMPLE_LMK_USE_REAPER
	/* Prepare the victim for the OOM reaper */
	if (!cmpxchg(&vtsk->signal->oom_mm, NULL, vtsk->mm)) {
		atomic_inc(&vtsk->signal->oom_mm->mm_count);
		set_bit(MMF_OOM_VICTIM, &vtsk->mm->flags);
	}
#endif

	/* Force the kill signal in order to accelerate the victim's death */
	do_send_sig_info(SIGKILL, SIG_INFO_TYPE, vtsk, true);

	/* Finally unlock the victim's mm lock */
	task_unlock(vtsk);

#ifdef CONFIG_ANDROID_SIMPLE_LMK_USE_REAPER
	/* Pass the victim onto the OOM reaper to quickly free its anon pages */
	wake_oom_reaper(vtsk);
#endif
}

static void kill_victims_and_wait(struct victim_info *varr, int count)
{
	static DECLARE_WAIT_QUEUE_HEAD(victim_waitq);
	atomic_t victim_count = ATOMIC_INIT(count);
	int i;

	for (i = 0; i < count; i++) {
		struct victim_info *victim = varr + i;

		pr_info("killing %s with adj %d to free %lu kiB\n",
			victim->tsk->comm, victim->tsk->signal->oom_score_adj,
			victim->size << (PAGE_SHIFT - 10));

		kill_vtsk(victim->tsk, &victim_waitq, &victim_count);
	}

	/* Release the RCU read lock and re-enable preemption */
	rcu_read_unlock();
	preempt_enable();

	/* Try to speed up the death process now that we can schedule again */
	for (i = 0; i < count; i++) {
		struct task_struct *vtsk = varr[i].tsk;

		/* Increase the victim's priority to make it die faster */
		set_user_nice(vtsk, MIN_NICE);

		/* Allow the victim to run on any CPU */
		set_cpus_allowed_ptr(vtsk, cpu_all_mask);

		/* Release the victim reference acquired in find_victims */
		put_task_struct(vtsk);
	}

	/* Wait until all the victims die */
	wait_event(victim_waitq, !atomic_read(&victim_count));
}

static void scan_and_kill(unsigned long pages_needed)
{
	struct victim_info victims[MAX_VICTIMS];
	int i, nr_to_kill = 0, nr_victims = 0;
	unsigned long pages_found = 0;

	/*
	 * These are released in kill_victims_and_wait. Preemption is disabled
	 * so that the kill process isn't interrupted. The RCU read lock is held
	 * so that the process list can be traversed several times throughout
	 * the entire scan-and-kill process.
	 */
	preempt_disable();
	rcu_read_lock();

	for (i = 1; i < ARRAY_SIZE(adj_prio); i++) {
		pages_found += find_victims(victims, &nr_victims, MAX_VICTIMS,
					    adj_prio[i], adj_prio[i - 1]);
		if (pages_found >= pages_needed || nr_victims == MAX_VICTIMS)
			break;
	}

	/*
	 * Calculate the number of tasks that need to be killed and release the
	 * the references to those that won't.
	 */
	for (i = 0, pages_found = 0; i < nr_victims; i++) {
		struct victim_info *victim = &victims[i];

		if (pages_found >= pages_needed) {
			task_unlock(victim->tsk);
			put_task_struct(victim->tsk);
			continue;
		}

		pages_found += victim->size;
		nr_to_kill++;
	}

	kill_victims_and_wait(victims, nr_to_kill);
}

static int simple_lmk_reclaim_thread(void *data)
{
	static const struct sched_param sched_max_rt_prio = {
		.sched_priority = MAX_RT_PRIO - 1
	};

	sched_setscheduler_nocheck(current, SCHED_FIFO, &sched_max_rt_prio);

	while (1) {
		int curr_oom_cnt, prev_oom_cnt = 0;
		bool should_stop = false;

		wait_event(oom_waitq, (should_stop = kthread_should_stop()) ||
				      (curr_oom_cnt = atomic_read(&oom_count)));

		if (should_stop)
			break;

		/*
		 * Kill a batch of processes and wait for their memory to be
		 * freed. After their memory is freed, sleep for one jiffy to
		 * allow OOM'd allocations a chance to scavenge for the
		 * newly-freed pages. Rinse and repeat while monitoring the
		 * pressure of OOM'd memory allocations; if the number of OOM'd
		 * allocations goes down, then stop killing. Conversely, keep
		 * killing when the OOM'd allocation count remains stagnant or
		 * goes up.
		 */
		do {
			if (curr_oom_cnt >= prev_oom_cnt)
				scan_and_kill(MIN_FREE_PAGES);
			prev_oom_cnt = curr_oom_cnt;
			while (schedule_timeout_uninterruptible(1));
		} while ((curr_oom_cnt = atomic_read(&oom_count)));
	}

	return 0;
}

void simple_lmk_start_reclaim(void)
{
	if (atomic_inc_return(&oom_count) == 1)
		wake_up(&oom_waitq);
}

void simple_lmk_stop_reclaim(void)
{
	atomic_dec(&oom_count);
}

/* Initialize Simple LMK when LMKD in Android writes to the minfree parameter */
static int simple_lmk_init_set(const char *val, const struct kernel_param *kp)
{
	static atomic_t init_done = ATOMIC_INIT(0);
	struct task_struct *thread;

	if (atomic_cmpxchg(&init_done, 0, 1))
		return 0;

	thread = kthread_run_perf_critical(simple_lmk_reclaim_thread, NULL,
					   "simple_lmkd");
	if (IS_ERR(thread))
		panic("Failed to start Simple LMK reclaim thread");

	return 0;
}

static const struct kernel_param_ops simple_lmk_init_ops = {
	.set = simple_lmk_init_set
};

/* Needed to prevent Android from thinking there's no LMK and thus rebooting */
#undef MODULE_PARAM_PREFIX
#define MODULE_PARAM_PREFIX "lowmemorykiller."
module_param_cb(minfree, &simple_lmk_init_ops, NULL, 0200);
