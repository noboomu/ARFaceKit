//
//  HCMatrixObject.swift
//  KalmanFilter
//
//  Created by Hypercube on 4/26/17.
//  Copyright © 2017 Hypercube. All rights reserved.
//

import Foundation
import Accelerate

class HCMatrixObject
{
    //MARK: - HCMatrixObject properties
    
    /// Number of Rows in Matrix
    private var rows: Int
    
    /// Number of Columns in Matrix
    private var columns: Int
    
    /// Surge Matrix object
    var matrix: Matrix<Float>
    
    //MARK: - Initialization
    
    /// Initailization of matrix with specified numbers of rows and columns
    init(rows:Int,columns:Int) {
        self.rows = rows;
        self.columns = columns;
        self.matrix = Matrix<Float>(rows: self.rows, columns: self.columns, repeatedValue: 0.0)
    }
    
    //MARK: - HCMatrixObject functions
    
    /// getIdentityMatrix Function
    /// ==========================
    /// For some dimension dim, return identity matrix object
    ///
    /// - parameters:
    ///   - dim: dimension of desired identity matrix
    /// - returns: identity matrix object
    static func getIdentityMatrix(dim:Int) -> HCMatrixObject
    {
        let identityMatrix = HCMatrixObject(rows: dim, columns: dim)
        
        for i in 0..<dim
        {
            for j in 0..<dim
            {
                if i == j
                {
                    identityMatrix.matrix[i,j] = 1.0
                }
            }
        }
        
        return identityMatrix
    }
    
    /// addElement Function
    /// ===================
    /// Add double value on (i,j) position in matrix
    ///
    /// - parameters:
    ///   - i: row of matrix
    ///   - j: column of matrix
    ///   - value: double value to add in matrix
    public func addElement(i:Int,j:Int,value:Float)
    {
        if self.matrix.rows > i && self.matrix.columns > j
        {
            self.matrix[i,j] = value;
        }
        else
        {
            print("error")
        }
    }
    
    /// setMatrix Function
    /// ==================
    /// Set complete matrix
    ///
    /// - parameters:
    ///   - matrix: array of array of double values
    public func setMatrix(matrix:[[Float]])
    {
        if self.matrix.rows > 0
        {
            if (matrix.count == self.matrix.rows) && (matrix[0].count == self.matrix.columns)
            {
                self.matrix = Matrix<Float>(matrix)
            }
        }
    }
    
    /// getElement Function
    /// ===================
    /// Returns double value on specific position of matrix
    ///
    /// - parameters:
    ///   - i: row of matrix
    ///   - j: column of matrix
    
    public func getElement(i:Int,j:Int) -> Float?
    {
        if self.matrix.rows <= i && self.matrix.columns <= j
        {
            return self.matrix[i,j]
        }
        else
        {
            print("error")
            return nil
        }
    }
    
    public func transpose( x: Matrix<Float>) -> Matrix<Float> {
        var results = Matrix<Float>(rows: x.columns, columns: x.rows, repeatedValue: 0.0)
        results.grid.withUnsafeMutableBufferPointer { pointer in
            vDSP_mtrans(x.grid, 1, pointer.baseAddress!, 1, vDSP_Length(x.columns), vDSP_Length(x.rows))
        }
        
        return results
    }
    
    public class func mul( x: Matrix<Float>,  y: Matrix<Float>) -> Matrix<Float> {
 
        var results = Matrix<Float>(rows: x.rows, columns: y.columns, repeatedValue: 0.0)
        results.grid.withUnsafeMutableBufferPointer { pointer in
            cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans, Int32(x.rows), Int32(y.columns), Int32(x.columns), 1.0, x.grid, Int32(x.columns), y.grid, Int32(y.columns), 0.0, pointer.baseAddress!, Int32(y.columns))
        }
        
        return results
    }
    
    public func inv( x: Matrix<Float>) -> Matrix<Float> {
 
        var results = x
        
        var ipiv = [__CLPK_integer](repeating: 0, count: x.rows * x.rows)
        var lwork = __CLPK_integer(x.columns * x.columns)
        var work = [CFloat](repeating: 0.0, count: Int(lwork))
        var error: __CLPK_integer = 0
        var nc = __CLPK_integer(x.columns)
        
        withUnsafeMutablePointers(&nc, &lwork, &error) { nc, lwork, error in
            withUnsafeMutableMemory(&ipiv, &work, &(results.grid)) { ipiv, work, grid in
                sgetrf_(nc, nc, grid.pointer, nc, ipiv.pointer, error)
                sgetri_(nc, grid.pointer, nc, ipiv.pointer, work.pointer, lwork, error)
            }
        }
        
        
        return results
    }
    
    /// Transpose Matrix Function
    /// =========================
    /// Returns result HCMatrixObject of transpose operation
    ///
    /// - returns: transposed HCMatrixObject object
    public func transpose() -> HCMatrixObject?
    {
        let result = HCMatrixObject(rows: self.rows, columns: self.columns)
        
        result.matrix = self.transpose(x:self.matrix)
        
        
        return result
    }
    
    /// Inverse Matrix Function
    /// =======================
    /// Returns inverse matrix object
    ///
    /// - returns: inverse matrix object
    public func inverseMatrix() -> HCMatrixObject?
    {
        let result = HCMatrixObject(rows: rows, columns: columns)
        
      
        result.matrix = self.inv(x:self.matrix)
        
        return result
    }
    
    /// Print Matrix Function
    /// =====================
    /// Printing the entire matrix
    public func printMatrix()
    {
        for i in 0..<self.matrix.rows
        {
            for j in 0..<self.matrix.columns
            {
                print("\(self.matrix[i,j]) ")
            }
            print("---")
        }
    }
    
    
    public class func add(  x: Matrix<Float>,   y: Matrix<Float>) -> Matrix<Float> {
        precondition(x.rows == y.rows && x.columns == y.columns, "Matrix dimensions not compatible with addition")
        
        var results = y
        results.grid.withUnsafeMutableBufferPointer { pointer in
            cblas_saxpy(Int32(x.grid.count), 1.0, x.grid, 1, pointer.baseAddress!, 1)
        }
        
        return results
    }
    //MARK: - Predefined HCMatrixObject operators
    
    /// Predefined + operator
    /// =====================
    /// Returns result HCMatrixObject of addition operation
    ///
    /// - parameters:
    ///   - left: left addition HCMatrixObject operand
    ///   - right: right addition HCMatrixObject operand
    /// - returns: result HCMatrixObject object of addition operation
    static func +(left:HCMatrixObject, right:HCMatrixObject) ->HCMatrixObject?
    {
        let result = HCMatrixObject(rows: left.rows, columns: left.columns)
        
        result.matrix = add(x:left.matrix,y:right.matrix)
        
        return result
    }
    
    /// Predefined - operator
    /// =====================
    /// Returns result HCMatrixObject of subtraction operation
    ///
    /// - parameters:
    ///   - left: left subtraction HCMatrixObject operand
    ///   - right: right subtraction HCMatrixObject operand
    /// - returns: result HCMatrixObject object of subtraction operation
    static func -(left:HCMatrixObject, right:HCMatrixObject) ->HCMatrixObject?
    {
        let result = HCMatrixObject(rows: left.rows, columns: left.columns)
        
        if(left.rows == right.rows && left.columns == right.columns)
        {
            for i in 0..<left.matrix.rows
            {
                for j in 0..<left.matrix.columns
                {
                    result.matrix[i,j] = left.matrix[i,j] - right.matrix[i,j]
                }
            }
        }
        
        return result
    }
    
    /// Predefined * operator
    /// =====================
    /// Returns result HCMatrixObject of multiplication operation
    ///
    /// - parameters:
    ///   - left: left multiplication HCMatrixObject operand
    ///   - right: right multiplication HCMatrixObject operand
    /// - returns: result HCMatrixObject object of multiplication operation
    static func *(left:HCMatrixObject, right:HCMatrixObject) -> HCMatrixObject?
    {
 
        var resultMatrix = mul(x:left.matrix,y:right.matrix)
        
        let result = HCMatrixObject(rows: resultMatrix.rows,columns: resultMatrix.columns)
        result.matrix = resultMatrix
        
        return result
    }
}

