# 8086 test program for the APB bench: 16 KB image at FC000, CS = FC00.
	.code16
	.intel_syntax noprefix
	.text
start:
	cli
	xor	ax, ax
	mov	ss, ax
	mov	sp, 0x8000
	mov	ds, ax
	mov	es, ax
	mov	word ptr [0x0000], 0x1234
	mov	byte ptr [0x0002], 0xAB
	mov	byte ptr [0x0005], 0xCD
	mov	word ptr [0x0007], 0x5678
	# one word from offset 0x10 of every 16 KB page -> 0:0100 + 2p
	xor	bx, bx
	mov	di, 0x100
scan:
	mov	ax, bx
	mov	cl, 10
	shl	ax, cl
	mov	es, ax
	mov	ax, es:[0x10]
	mov	[di], ax
	add	di, 2
	inc	bx
	cmp	bx, 64
	jne	scan
	# I/O window
	mov	dx, 0x4140
	mov	ax, 0x00C8
	out	dx, ax
	mov	dx, 0x4020
	mov	al, 0x5A
	out	dx, al
	mov	dx, 0x4061
	mov	al, 0x3C
	out	dx, al
	mov	dx, 0x4060
	in	al, dx
	mov	[0x200], al
	mov	dx, 0x4140
	in	ax, dx
	mov	[0x202], ax
	mov	dx, 0x4063
	in	al, dx
	mov	[0x204], al
	# odd stack: split word pushes and pops
	mov	sp, 0x7FFF
	mov	ax, 0x1357
	push	ax
	mov	bx, 0x2468
	push	bx
	pop	dx
	pop	si
	mov	[0x206], dx
	mov	[0x208], si
	mov	word ptr [0x20A], 0
	# REP MOVSW at an odd address, after an instruction whose end overlaps the prefix
	xor	ax, ax
	mov	es, ax
	mov	si, 0x100
	mov	di, 0x220
	mov	cx, 9
	.balign	2
	nop
	shr	cx, 1
	rep	movsw
	mov	[0x20E], cx
	# interrupts: NVI at vector FF, 8259 IR4 at vector 8
	mov	word ptr [0x3FC], offset nvi_h
	mov	word ptr [0x3FE], 0xFC00
	mov	word ptr [0x20], offset vi_h
	mov	word ptr [0x22], 0xFC00
	mov	word ptr [0x300], 0
	mov	dx, 0x4180
	mov	al, 1
	out	dx, al
	sti
wait_int:
	mov	cx, 10
	xor	di, di
count:
	push	cx
	inc	di
	pop	cx
	loop	count
	cmp	di, 10
	je	count_ok
	mov	word ptr [0x20A], 0xBAD0
count_ok:
	cmp	byte ptr [0x300], 0
	je	wait_int
	cmp	byte ptr [0x301], 0
	je	wait_int
	cli
	mov	dx, 0x4180
	mov	al, 2
	out	dx, al
	mov	dx, 0x7FFA
	out	dx, ax
	hlt
# NVI handler on its own odd stack, as the APB ROM's tick handler
nvi_h:
	push	ds
	mov	[0x210], ss
	mov	[0x212], sp
	mov	[0x214], ax
	cli
	xor	ax, ax
	mov	ss, ax
	mov	sp, 0x6549
	push	word ptr [0x214]
	push	bx
	push	cx
	push	dx
	pushf
	mov	bx, 0x8888
	mov	cx, 0x7777
	mov	dx, 0x6666
	inc	byte ptr [0x300]
	popf
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	cli
	mov	ss, [0x210]
	mov	sp, [0x212]
	pop	ds
	sti
	iret
vi_h:
	mov	[0x20C], sp
	inc	byte ptr [0x301]
	iret
	.org	0x3FF0
	ljmp	0xFC00, 0
	.org	0x4000
