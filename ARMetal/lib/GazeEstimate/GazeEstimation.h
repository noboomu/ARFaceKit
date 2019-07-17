#ifndef __GAZEESTIMATION_h_
#define __GAZEESTIMATION_h_

#include "opencv2/core/core.hpp"
#include "LandmarkCoreIncludes.h"

namespace GazeEstimate
{

    void EstimateGaze(const LandmarkDetector::CLNF& clnf_model, cv::Point3f& gaze_absolute,   float fx, float fy, float cx, float cy, bool left_eye);
    
    void EstimateEyeGaze(const LandmarkDetector::CLNF& clnf_model, cv::Point3f& gaze_absolute,cv::Vec6d& headPose, float fx, float fy, float cx, float cy, bool left_eye);
    
    // Getting the gaze angle in radians with respect to the world coordinates (camera plane), when looking ahead straight at camera plane the gaze angle will be (0,0)
    cv::Vec2d GetGazeAngle(cv::Point3f& gaze_vector_1, cv::Point3f& gaze_vector_2);
    
    

    cv::Point3f GetPupilPosition(cv::Mat_<double> eyeLdmks3d);
 
 
}
#endif
