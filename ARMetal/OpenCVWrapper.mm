//
//  OpenCVWrapper.m
//  ARMetal
//
//  Created by joshua bauer on 4/4/18.
//  Copyright © 2019 Sinistral Systems. All rights reserved.
//

#import "OpenCVWrapper.h"

#include <stdlib.h>
#include <iostream>
#include <sstream>
#include <chrono>

#include "tbb/tbb.h"

#import <opencv2/core.hpp>
#import <opencv2/imgcodecs/ios.h>
#import <opencv2/imgproc/imgproc.hpp>

 #import <opencv2/video/tracking.hpp>

#include "GazeEstimation.h"
#include "LandmarkCoreIncludes.h"

#import <AVFoundation/AVFoundation.h>


using namespace cv;

static int format_opencv = CV_8UC4;

static long RESET_ITERATION = 30;

@implementation OpenCVWrapper {
    
    LandmarkDetector::CLNF *leftEyeModel;
    LandmarkDetector::CLNF *rightEyeModel;

    LandmarkDetector::FaceModelParameters leftEyeParameters;
    LandmarkDetector::FaceModelParameters rightEyeParameters;

    cv::Mat dummyImage;
    
    cv::KalmanFilter *kf;
    
    std::vector<cv::Point> predictedMousePositions;                 // declare 3 vectors for predicted, actual, and corrected positions
    std::vector<cv::Point> actualMousePositions;
    std::vector<cv::Point> correctedMousePositions;
    
    long currentIteration;
  
    simd_float4 instrinsics;
    
    vector_float2 gazeAngle;
    vector_float3 leftEyeCenter;
    vector_float3 rightEyeCenter;
    vector_float3 leftEyeGaze;
    vector_float3 rightEyeGaze;
    
    BOOL hasInstrinsics;
}

-(void) resetModels
{
    if(leftEyeModel->tracking_initialised)
    {
        leftEyeModel->Reset();
    }
    if(rightEyeModel->tracking_initialised)
    {
        rightEyeModel->Reset();
    }
    
    currentIteration = 0;
    
    gazeAngle = simd_make_float2(0.0f,0.0f);
    leftEyeCenter = simd_make_float3(0.0f,0.0f,0.0f);
    rightEyeCenter = simd_make_float3(0.0f,0.0f,0.0f);
    leftEyeGaze = simd_make_float3(0.0f,0.0f,0.0f);
    rightEyeGaze = simd_make_float3(0.0f,0.0f,0.0f);
}

- (void) setIntrinsics:(simd_float4) cameraInstrinsics
{
    instrinsics = cameraInstrinsics;
    hasInstrinsics = true;
}

- (void) loadModels
{
    leftEyeParameters.validate_detections = false;
    leftEyeParameters.multi_view = false;
    leftEyeParameters.quiet_mode = false;
    leftEyeParameters.refine_parameters = false;
    leftEyeParameters.use_face_template = false;
    leftEyeParameters.reinit_video_every = 60;
    leftEyeParameters.num_optimisation_iteration = 5;
    leftEyeParameters.track_gaze = true;
    
    rightEyeParameters.validate_detections = false;
    rightEyeParameters.multi_view = false;
    rightEyeParameters.quiet_mode = false;
    rightEyeParameters.refine_parameters = false;
    rightEyeParameters.use_face_template = false;
    rightEyeParameters.reinit_video_every = 60;
    rightEyeParameters.num_optimisation_iteration = 5;
    rightEyeParameters.track_gaze = true;
    
    NSString* eyeModelPath = [[NSBundle mainBundle] pathForResource:@"model_eye" ofType:nil];
 
    NSString *leftModelPath = [eyeModelPath stringByAppendingPathComponent:@"main_clnf_synth_left.txt"];
    NSString *rightModelPath = [eyeModelPath stringByAppendingPathComponent:@"main_clnf_synth_right.txt"];

    NSLog(@"lefT: %@ right: %@ all: %@", leftModelPath, rightModelPath, eyeModelPath);
    
    leftEyeModel = new LandmarkDetector::CLNF(std::string([leftModelPath UTF8String]));
    rightEyeModel = new LandmarkDetector::CLNF(std::string([rightModelPath UTF8String]));

    dummyImage = cv::Mat();
    
    [self resetModels];
    
}

-(void) detectEyeLandmarks:(SCNNode *) node
                     leftTexture: (id<MTLTexture>) leftTexture
                         leftOffset:(simd_float2) leftOffset
                         leftBounds:(CGRect) leftBounds
                    rightTexture: (id<MTLTexture>) rightTexture
                        rightOffset:(simd_float2) rightOffset
                        rightBounds:(CGRect) rightBounds
{
    // [Tx, Ty, Tz, Eul_x, Eul_y, Eul_z]
    
    simd_float3 position =  node.simdWorldPosition;
    simd_float3 euler =  node.simdEulerAngles;
    
   // NSLog(@"Tx: %f Ty: %f Tz: %f Ex: %f Ey: %f Ez: %f", position.x,position.y,position.z,euler.x,euler.y,euler.z);

 
    
    cv::Vec6d poseEstimate(position.x,position.y,position.z,euler.x,euler.y,euler.z);
    
//    vector_float3 leftEyeCenter = simd_make_float3(0.0f,0.0f,0.0f);
//    vector_float3 rightEyeCenter = simd_make_float3(0.0f,0.0f,0.0f);
//    vector_float2 gazeAngle simd_make_float2(0.0f,0.0f);
    
//    vector_float3 leftGaze = simd_make_float3(0.0f,0.0f,-1.0f);
//    vector_float3 rightGaze = simd_make_float3(0.0f,0.0f,-1.0f);

    cv::Rect_<double> leftBBox;
    cv::Rect_<double> rightBBox;
    
    BOOL detectedLeft = false;
    BOOL detectedRight = false;
    
 
    
    cv::Mat_<uchar> leftGrayscaleImage;
    cv::Mat_<uchar> rightGrayscaleImage;
 
   // auto start = std::chrono::high_resolution_clock::now();

    bool doReset = currentIteration % RESET_ITERATION == 0;
    
    tbb::parallel_for(0, (int)2, [&](int i)
    {
        if( i == 0 && leftTexture != nil )
        {
            if( doReset )
            {
                leftEyeModel->Reset();
            }
            
            void* bufferAddress = [leftTexture buffer].contents;
            size_t width = leftTexture.width;
            size_t height = leftTexture.height;
            size_t bytesPerRow = 4 * width;
            
            cv::Mat image((int)height, (int)width, format_opencv, bufferAddress, bytesPerRow);
            
            cv::cvtColor(image, leftGrayscaleImage, CV_BGRA2GRAY);
            
            leftBBox.x = leftBounds.origin.x;
            leftBBox.y = leftBounds.origin.y;
            leftBBox.width = leftBounds.size.width;
            leftBBox.height = leftBounds.size.height;
            
           // leftEyeModel->pdm.CalcParams(leftEyeModel->params_global, leftBBox, leftEyeModel->params_local);
           //  detectedLeft = leftEyeModel->DetectLandmarks(leftGrayscaleImage,  dummyImage, eyeParameters);

           detectedLeft = LandmarkDetector::DetectLandmarksInVideo(leftGrayscaleImage, leftBBox, *leftEyeModel, leftEyeParameters);
            
 
            if(   detectedLeft )
            {
                int halfLength = (leftEyeModel->detected_landmarks.rows/2);
                
                std::vector<cv::Point2d> eyeCoords2d;
                
                for(int i = 0; i < halfLength; i++)
                {
                    const double* x = leftEyeModel->detected_landmarks.ptr<double>(i);
                    const double* y = leftEyeModel->detected_landmarks.ptr<double>(i + halfLength);
                    
                    eyeCoords2d.push_back( cv::Point2d( leftOffset.x + (*x - 5.0), leftOffset.y + (*y - 10.0) ) );
                }
                
                cv::Point3f gazeDirection(0, 0, -1);
                
                GazeEstimate::EstimateEyeGaze(*leftEyeModel, gazeDirection, poseEstimate, instrinsics.x, instrinsics.y, instrinsics.z, instrinsics.w, true);
                
                /*
                 Estimator swaps left and right eyes
                 */
                
                rightEyeGaze = simd_make_float3((float)gazeDirection.x,(float)gazeDirection.y,(float)-gazeDirection.z);
                
                rightEyeCenter =  simd_make_float3((float)( (eyeCoords2d.at(0).x + eyeCoords2d.at(4).x) / 2.0   ), (float)( (eyeCoords2d.at(0).y + eyeCoords2d.at(4).y) / 2.0   ), 0.0f);
            }
        }
        else if( i == 1 && rightTexture != nil )
        {
            
            if( doReset )
            {
               rightEyeModel->Reset();
            }
            
                void* bufferAddress = [rightTexture buffer].contents;
                size_t width = rightTexture.width;
                size_t height = rightTexture.height;
                size_t bytesPerRow = 4 * width;
                
                cv::Mat image((int)height, (int)width, format_opencv, bufferAddress, bytesPerRow);
                
                
                cv::cvtColor(image, rightGrayscaleImage, CV_BGRA2GRAY);
                
                rightBBox.x = rightBounds.origin.x;
                rightBBox.y = rightBounds.origin.y;
                rightBBox.width = rightBounds.size.width;
                rightBBox.height = rightBounds.size.height;
                
         
            
            //rightEyeModel->pdm.CalcParams(rightEyeModel->params_global, rightBBox, rightEyeModel->params_local);
        
            //detectedRight = rightEyeModel->DetectLandmarks(rightGrayscaleImage,  dummyImage, eyeParameters);
            
            detectedRight = LandmarkDetector::DetectLandmarksInVideo(rightGrayscaleImage, rightBBox, *rightEyeModel, rightEyeParameters);

            
            if(rightTexture != nil  && detectedRight)
            {
                int halfLength = (rightEyeModel->detected_landmarks.rows/2);
                
                std::vector<cv::Point2d> eyeCoords2d;
                
                for(int i = 0; i < halfLength; i++)
                {
                    const double* x = rightEyeModel->detected_landmarks.ptr<double>(i);
                    const double* y = rightEyeModel->detected_landmarks.ptr<double>(i + halfLength);
                    eyeCoords2d.push_back( cv::Point2d( rightOffset.x + (*x - 5.0), rightOffset.y + (*y - 10.0) ) );
                }
                
                cv::Point3f gazeDirection(0, 0, 1);
                
                GazeEstimate::EstimateEyeGaze(*rightEyeModel, gazeDirection, poseEstimate, instrinsics.x, instrinsics.y, instrinsics.z, instrinsics.w, false);
                
                /*
                 Estimator swaps left and right eyes
                */
                
                leftEyeGaze = simd_make_float3((float)gazeDirection.x,(float)gazeDirection.y,(float)gazeDirection.z);
                
                leftEyeCenter =  simd_make_float3((float)( (eyeCoords2d.at(0).x + eyeCoords2d.at(4).x) / 2.0   ), (float)( (eyeCoords2d.at(0).y + eyeCoords2d.at(4).y) / 2.0   ), 0.0f);
            }
        }
    });
    
    
    if(detectedRight && detectedLeft)
    {
       // std::cout << "found 2 eyed" << std::endl;
        
        simd_float3 gazeVector = (leftEyeGaze + rightEyeGaze) / 2.0f;
        
        double angleX = atan2(gazeVector.x, -gazeVector.z);
        double angleY = atan2(gazeVector.y, -gazeVector.z);
        
        gazeAngle =  simd_make_float2((float)angleX, (float)angleY);
    }
    
   // auto finish = std::chrono::high_resolution_clock::now();
    //
   // std::chrono::duration<double> elapsed = finish - start;
    //
   // std::cout << "Elapsed time for both eyes: " << elapsed.count() <<  " gaze x: " << gazeAngle.x << " x " << gazeAngle.y << " s\n";
    
    currentIteration = currentIteration + 1;
    
    if( doReset )
    {
        currentIteration = 0;
    }
    
    return;
    
}

-(void) initKalmanFilter
{

   cv::KalmanFilter kalmanFilter(4,2,0);

   kf = &kalmanFilter;

    float fltTransitionMatrixValues[4][4] = { { 1, 0, 1, 0 },           // declare an array of floats to feed into Kalman Filter Transition Matrix, also known as State Transition Model
        { 0, 1, 0, 1 },
        { 0, 0, 1, 0 },
        { 0, 0, 0, 1 } };

    kalmanFilter.transitionMatrix = cv::Mat(4, 4, CV_32F, fltTransitionMatrixValues);       // set Transition Matrix

    float fltMeasurementMatrixValues[2][4] = { { 1, 0, 0, 0 },          // declare an array of floats to feed into Kalman Filter Measurement Matrix, also known as Measurement Model
        { 0, 1, 0, 0 } };

    kalmanFilter.measurementMatrix = cv::Mat(2, 4, CV_32F, fltMeasurementMatrixValues);     // set Measurement Matrix

    cv::setIdentity(kalmanFilter.processNoiseCov, cv::Scalar::all(0.0001));           // default is 1, for smoothing try 0.0001
    cv::setIdentity(kalmanFilter.measurementNoiseCov, cv::Scalar::all(10));         // default is 1, for smoothing try 10
    cv::setIdentity(kalmanFilter.errorCovPost, cv::Scalar::all(0.1));               // default is 0, for smoothing try 0.1


}

-(vector_float3) leftEyeCenter
{
    return leftEyeCenter;
}

-(vector_float3) rightEyeCenter
{
    return rightEyeCenter;
}

-(vector_float3) leftEyeGaze
{
    return leftEyeGaze;
}

-(vector_float3) rightEyeGaze
{
     return rightEyeGaze;
}

-(vector_float2) gaze
{
    return gazeAngle;
}


@end
