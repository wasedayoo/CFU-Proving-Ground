	.file	"main.c"
	.option nopic
	.attribute arch, "rv32i2p1_m2p0_zmmul1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.section	.rodata.str1.4,"aMS",@progbits,1
	.align	2
.LC0:
	.string	"steps :"
	.text
	.align	2
	.globl	RandomChar
	.type	RandomChar, @function
RandomChar:
	addi	sp,sp,-48
	lui	a5,%hi(.LC0)
	sw	s0,40(sp)
	sw	s1,36(sp)
	sw	s2,32(sp)
	sw	s3,28(sp)
	sw	s4,24(sp)
	sw	ra,44(sp)
	sw	s5,20(sp)
	sw	s6,16(sp)
	sw	s7,12(sp)
	li	s0,1
	li	s1,0
	li	s3,26
	li	s2,240
	addi	s4,a5,%lo(.LC0)
.L2:
	call	rand
	mv	s5,a0
	call	rand
	mv	s6,a0
	call	rand
	mv	s7,a0
	call	rand
	rem	a2,s5,s3
	andi	a3,a0,7
	li	a4,1
	rem	a1,s7,s2
	addi	a2,a2,65
	andi	a2,a2,0xff
	rem	a0,s6,s2
	call	pg_lcd_draw_char
	li	a1,14
	li	a0,0
	call	pg_lcd_set_pos
	mv	a0,s4
	call	pg_lcd_prints
	mv	a0,s0
	mv	a1,s1
	call	pg_lcd_printd
	addi	a5,s0,1
	sltu	a4,a5,s0
	add	s1,a4,s1
	mv	s0,a5
	j	.L2
	.size	RandomChar, .-RandomChar
	.section	.text.startup,"ax",@progbits
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-16
	sw	ra,12(sp)
	call	pg_lcd_reset
	call	RandomChar
	.size	main, .-main
	.ident	"GCC: (g5115c7e447) 15.2.0"
	.section	.note.GNU-stack,"",@progbits
