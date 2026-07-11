	.file	"main.c"
	.option nopic
	.attribute arch, "rv64i2p1_m2p0_zmmul1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.rodata
	.align	3
.LC0:
	.string	"steps :"
	.text
	.align	2
	.globl	RandomChar
	.type	RandomChar, @function
RandomChar:
	addi	sp,sp,-48
	sd	ra,40(sp)
	sd	s0,32(sp)
	sd	s1,24(sp)
	sd	s2,16(sp)
	addi	s0,sp,48
	sw	zero,-36(s0)
.L2:
	lw	a5,-36(s0)
	addiw	a5,a5,1
	sw	a5,-36(s0)
	call	rand
	mv	a5,a0
	sext.w	a3,a5
	li	a4,1321529344
	addi	a4,a4,-945
	mul	a4,a3,a4
	srli	a4,a4,32
	sraiw	a4,a4,3
	mv	a3,a4
	sraiw	a4,a5,31
	subw	a4,a3,a4
	mv	a3,a4
	li	a4,26
	mulw	a4,a3,a4
	subw	a5,a5,a4
	sext.w	a5,a5
	andi	a5,a5,0xff
	addiw	a5,a5,65
	sb	a5,-37(s0)
	call	rand
	mv	a5,a0
	sext.w	a3,a5
	li	a4,-2004316160
	addi	a4,a4,-1911
	mul	a4,a3,a4
	srli	a4,a4,32
	addw	a4,a5,a4
	sraiw	a4,a4,7
	mv	a3,a4
	sraiw	a4,a5,31
	subw	a4,a3,a4
	mv	a3,a4
	mv	a4,a3
	slliw	a4,a4,4
	subw	a4,a4,a3
	slliw	a4,a4,4
	subw	a5,a5,a4
	sext.w	s1,a5
	call	rand
	mv	a5,a0
	sext.w	a3,a5
	li	a4,-2004316160
	addi	a4,a4,-1911
	mul	a4,a3,a4
	srli	a4,a4,32
	addw	a4,a5,a4
	sraiw	a4,a4,7
	mv	a3,a4
	sraiw	a4,a5,31
	subw	a4,a3,a4
	mv	a3,a4
	mv	a4,a3
	slliw	a4,a4,4
	subw	a4,a4,a3
	slliw	a4,a4,4
	subw	a5,a5,a4
	sext.w	s2,a5
	call	rand
	mv	a5,a0
	andi	a5,a5,0xff
	andi	a5,a5,7
	andi	a3,a5,0xff
	lbu	a5,-37(s0)
	li	a4,1
	mv	a2,a5
	mv	a1,s2
	mv	a0,s1
	call	pg_lcd_draw_char
	li	a1,14
	li	a0,0
	call	pg_lcd_set_pos
	lui	a5,%hi(.LC0)
	addi	a0,a5,%lo(.LC0)
	call	pg_lcd_prints
	lw	a5,-36(s0)
	mv	a0,a5
	call	pg_lcd_printd
	j	.L2
	.size	RandomChar, .-RandomChar
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32
	sd	ra,24(sp)
	sd	s0,16(sp)
	addi	s0,sp,32
	call	pg_lcd_reset
	call	RandomChar
	lui	a5,%hi(.LC1)
	lw	a5,%lo(.LC1)(a5)
	sw	a5,-20(s0)
	lui	a5,%hi(.LC2)
	lw	a5,%lo(.LC2)(a5)
	sw	a5,-24(s0)
	lw	a1,-24(s0)
	lw	a0,-20(s0)
	call	__mulsf3
	mv	a5,a0
	sw	a5,-28(s0)
	li	a5,0
	mv	a0,a5
	ld	ra,24(sp)
	ld	s0,16(sp)
	addi	sp,sp,32
	jr	ra
	.size	main, .-main
	.section	.rodata
	.align	2
.LC1:
	.word	1069966950
	.align	2
.LC2:
	.word	1067198710
	.globl	__mulsf3
	.ident	"GCC: (g5115c7e447) 15.2.0"
	.section	.note.GNU-stack,"",@progbits
