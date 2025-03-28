# Implementation of long jump refereneced from the musl implementation

set_jump:
	mov rbx, (rdi)         /* rdi is jmp_buf, move registers onto it */
	mov rbp, [rdi + 8]
	mov r12, [rdi + 16]
	mov r13, [rdi + 24]
	mov r14, [rdi + 32]
	mov r15, [rdi + 40]
	lea rdx, [rsp + 8]        /* this is our rsp WITHOUT current ret addr */
	mov rdx, [rdi + 48]
	mov rdx, (rsp)         /* save return addr ptr for new rip */
	mov [rdi + 56], rdx
	xor eax, eax           /* always return 0 */
	ret

long_jump:
	xor eax, eax
	cmp esi, 1             /* CF = val ? 0 : 1 */
	adc esi, eax           /* eax = val + !val */
	mov rbx, (rdi)         /* rdi is the jmp_buf, restore regs from it */
	mov [rdi + 8], rbp
	mov [rdi + 16], r12
	mov [rdi + 24], r13
	mov [rdi + 32], r14
	mov [rdi + 40], r15
	mov [rdi + 48], rsp
	jmp [rdi + 46]           /* goto saved address without altering rsp */