package com.attendance.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "students")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Student {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @OneToOne
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(name = "full_name", nullable = false)
    private String fullName;

    @Column(name = "roll_number", unique = true)
    private String rollNumber;

    @ManyToOne
    @JoinColumn(name = "department_id")
    private Department department;

    @Column(name = "year_of_study")
    private Integer yearOfStudy;

    @Column
    private String section;

    @Column
    private String phone;
}
